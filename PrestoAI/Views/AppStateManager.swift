import Foundation
import Combine
import IOKit
import CommonCrypto
import Network

// MARK: - App State Enum

enum AppState: Equatable {
    case anonymous       // Fresh install, no device ID yet
    case freeActive      // Has device ID, queries remaining > 0
    case freeExhausted   // Free lifetime queries used, no account
    case referralActive  // Referral reward active, queries allowed
    case paid            // Valid JWT, subscription active
}

// MARK: - App State Manager (single source of truth for auth + state)

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published private(set) var currentState: AppState = .freeActive
    @Published private(set) var queriesRemaining: Int = 10
    @Published private(set) var totalFreeQueries: Int = 10
    @Published private(set) var isOffline: Bool = false
    @Published var cachedPrice: String = "$5.99/month"
    
    // Keychain keys
    private let deviceIDKey = "presto.device_id"
    private let accessTokenKey = "presto.access_token"
    private let refreshTokenKey = "presto.refresh_token"

    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "ai.presto.networkMonitor")

    private init() {
        startNetworkMonitor()
        Task {
            await initializeState()
        }
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let wasOffline = self.isOffline
            let nowSatisfied = path.status == .satisfied

            if wasOffline && nowSatisfied {
                // Network recovered — re-initialize state
                Task { @MainActor in
                    self.isOffline = false
                    #if DEBUG
                    print("[AppState] Network recovered, re-initializing state...")
                    #endif
                    await self.initializeState()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    // MARK: - Device ID Management
    
    var deviceID: String {
        if let existing = KeychainHelper.load(key: deviceIDKey) {
            return existing
        }
        
        // Generate new device ID
        let newID = UUID().uuidString
        KeychainHelper.save(key: deviceIDKey, value: newID)
        #if DEBUG
        print("[AppState] Generated new device ID: \(newID)")
        #endif
        return newID
    }
    
    // MARK: - Hardware Fingerprint (anti-abuse)

    /// SHA-256 hash of the machine's IOPlatformUUID. Survives reinstalls, Keychain wipes,
    /// and user account changes. Sent as X-HW-Fingerprint header for server-side dedup.
    lazy var hardwareFingerprint: String = {
        var fingerprint = "unknown"
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if service != 0 {
            if let uuidData = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                // Hash it so we never send the raw hardware UUID
                let data = Data(uuidData.utf8)
                var hash = [UInt8](repeating: 0, count: 32)
                data.withUnsafeBytes { buffer in
                    CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
                }
                fingerprint = hash.map { String(format: "%02x", $0) }.joined()
            }
            IOObjectRelease(service)
        }
        return fingerprint
    }()

    // MARK: - Token Management (single source of truth)
    
    /// Current access token, or nil if not logged in.
    var accessToken: String? {
        KeychainHelper.load(key: accessTokenKey)
    }
    
    /// Current refresh token, or nil if not logged in.
    var refreshToken: String? {
        KeychainHelper.load(key: refreshTokenKey)
    }
    
    /// Legacy alias — returns the access token.
    var jwt: String? { accessToken }
    
    /// Save both tokens to Keychain. Call from APIService after login/register/refresh.
    @MainActor
    func saveTokens(access: String, refresh: String) {
        KeychainHelper.save(key: accessTokenKey, value: access)
        KeychainHelper.save(key: refreshTokenKey, value: refresh)
        #if DEBUG
        print("[AppState] Tokens saved to Keychain")
        #endif
    }
    
    /// Legacy helper — saves access token only (for backward compat with checkout flow).
    func saveJWT(_ token: String) {
        KeychainHelper.save(key: accessTokenKey, value: token)
        #if DEBUG
        print("[AppState] Access token saved to Keychain")
        #endif
    }
    
    private func clearTokens() {
        KeychainHelper.delete(key: accessTokenKey)
        KeychainHelper.delete(key: refreshTokenKey)
        #if DEBUG
        print("[AppState] Tokens cleared from Keychain")
        #endif
    }
    
    // MARK: - State Initialization & Updates
    
    @MainActor
    func initializeState() async {
        #if DEBUG
        print("[AppState] Initializing app state...")
        #endif
        
        // Check if we have a JWT
        if let token = accessToken {
            #if DEBUG
            print("[AppState] Found access token, validating...")
            #endif
            do {
                let status = try await APIService.shared.validateAuth(token: token)
                if status.state == "paid" {
                    currentState = .paid
                    #if DEBUG
                    print("[AppState] Token valid, state = .paid")
                    #endif
                    return
                } else {
                    // Subscription expired
                    clearTokens()
                    #if DEBUG
                    print("[AppState] Subscription expired, cleared tokens")
                    #endif
                }
            } catch {
                // #18 — Try refreshing before giving up; verify token was saved
                if await APIService.shared.refreshAccessToken() {
                    if let newToken = accessToken, !newToken.isEmpty {
                        do {
                            let status = try await APIService.shared.validateAuth(token: newToken)
                            if status.state == "paid" {
                                currentState = .paid
                                #if DEBUG
                                print("[AppState] Token refreshed, state = .paid")
                                #endif
                                return
                            }
                        } catch { /* fall through */ }
                    } else {
                        // Token refresh claimed success but token not in Keychain — retry once
                        #if DEBUG
                        print("[AppState] Token refresh succeeded but token not saved, retrying...")
                        #endif
                        if await APIService.shared.refreshAccessToken(), let retryToken = accessToken, !retryToken.isEmpty {
                            do {
                                let status = try await APIService.shared.validateAuth(token: retryToken)
                                if status.state == "paid" {
                                    currentState = .paid
                                    #if DEBUG
                                    print("[AppState] Token refreshed on retry, state = .paid")
                                    #endif
                                    return
                                }
                            } catch { /* fall through */ }
                        }
                    }
                }
                clearTokens()
                #if DEBUG
                print("[AppState] Token validation failed: \(error.localizedDescription)")
                #endif
            }
        }
        
        // No valid JWT — check device status
        let devID = deviceID  // generates one if needed
        
        do {
            let status = try await APIService.shared.checkDeviceStatus(deviceID: devID)
            queriesRemaining = status.queriesRemaining
            if let total = status.totalFreeQueries {
                totalFreeQueries = total
            }
            
            if status.queriesRemaining > 0 {
                currentState = .freeActive
                #if DEBUG
                print("[AppState] Device status: \(status.queriesRemaining) queries remaining, state = .freeActive")
                #endif
            } else {
                // Check if referral reward is active before marking as exhausted
                await checkReferralReward()
                if currentState != .referralActive {
                    currentState = .freeExhausted
                    #if DEBUG
                    print("[AppState] Device status: 0 queries remaining, state = .freeExhausted")
                    #endif
                } else {
                    #if DEBUG
                    print("[AppState] Device status: referral reward active, state = .referralActive")
                    #endif
                }
            }
        } catch {
            // #19 — Backend unreachable: do NOT grant free queries offline
            isOffline = true
            Analytics.shared.track("error.offlineDetected")
            currentState = .anonymous
            queriesRemaining = 0
            #if DEBUG
            print("[AppState] Backend unreachable, state = .anonymous (offline)")
            #endif
        }
    }
    
    @MainActor
    func updateAfterQuery(queriesRemaining: Int, state: String) {
        self.queriesRemaining = queriesRemaining
        
        switch state {
        case "free_active":
            currentState = .freeActive
        case "free_exhausted":
            currentState = .freeExhausted
        case "paid", "trial":
            currentState = .paid
        default:
            // Don't change state on unknown values — prevents the lockout bug
            #if DEBUG
            print("[AppState] Ignoring unknown state: \(state)")
            #endif
        }
        
        #if DEBUG
        print("[AppState] Updated after query: \(queriesRemaining) remaining, state = \(currentState)")
        #endif
    }
    
    @MainActor
    func setStateToPaid(jwt: String) {
        saveJWT(jwt)
        currentState = .paid
        #if DEBUG
        print("[AppState] State set to .paid")
        #endif
    }
    
    @MainActor
    func signOut() {
        // Invalidate refresh token on backend before clearing local state
        if let refreshToken = KeychainHelper.load(key: "presto.refresh_token") {
            Task {
                await APIService.shared.logout(refreshToken: refreshToken)
            }
        }
        clearTokens()
        // Keep device ID — free queries are lifetime
        currentState = .freeExhausted
        queriesRemaining = 0
        #if DEBUG
        print("[AppState] Signed out, state = .freeExhausted")
        #endif
    }
    
    // MARK: - Can Analyze Check
    
    /// Whether a referral reward is currently active (checked during state init)
    @Published private(set) var referralRewardActive = false

    @MainActor
    func checkReferralReward() async {
        let devID = deviceID
        do {
            let info = try await APIService.shared.getPaywallInfo(deviceID: devID)
            // Reward is active if it exists and hasn't expired
            if !info.canUseReferral, let expiresStr = info.rewardExpiresAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let expires = formatter.date(from: expiresStr), expires > Date() {
                    referralRewardActive = true
                    currentState = .referralActive
                    Analytics.shared.track("referral.rewardActivated")
                    return
                }
                // Also try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let expires = formatter.date(from: expiresStr), expires > Date() {
                    referralRewardActive = true
                    currentState = .referralActive
                    Analytics.shared.track("referral.rewardActivated")
                    return
                }
            }
            referralRewardActive = false
        } catch {
            referralRewardActive = false
        }
    }

    var canAnalyze: Bool {
        switch currentState {
        case .paid, .referralActive:
            return true
        case .freeActive:
            return queriesRemaining > 0
        case .freeExhausted, .anonymous:
            return false
        }
    }
}
