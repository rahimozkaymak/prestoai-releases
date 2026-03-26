import Foundation
import Combine
import IOKit
import CommonCrypto

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
    
    private init() {
        Task {
            await initializeState()
        }
    }
    
    // MARK: - Device ID Management
    
    var deviceID: String {
        if let existing = KeychainHelper.load(key: deviceIDKey) {
            return existing
        }
        
        // Generate new device ID
        let newID = UUID().uuidString
        KeychainHelper.save(key: deviceIDKey, value: newID)
        print("[AppState] Generated new device ID: \(newID)")
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
        print("[AppState] Tokens saved to Keychain")
    }
    
    /// Legacy helper — saves access token only (for backward compat with checkout flow).
    func saveJWT(_ token: String) {
        KeychainHelper.save(key: accessTokenKey, value: token)
        print("[AppState] Access token saved to Keychain")
    }
    
    private func clearTokens() {
        KeychainHelper.delete(key: accessTokenKey)
        KeychainHelper.delete(key: refreshTokenKey)
        print("[AppState] Tokens cleared from Keychain")
    }
    
    // MARK: - State Initialization & Updates
    
    @MainActor
    func initializeState() async {
        print("[AppState] Initializing app state...")
        
        // Check if we have a JWT
        if let token = accessToken {
            print("[AppState] Found access token, validating...")
            do {
                let status = try await APIService.shared.validateAuth(token: token)
                if status.state == "paid" {
                    currentState = .paid
                    print("[AppState] Token valid, state = .paid")
                    return
                } else {
                    // Subscription expired
                    clearTokens()
                    print("[AppState] Subscription expired, cleared tokens")
                }
            } catch {
                // #18 — Try refreshing before giving up; verify token was saved
                if await APIService.shared.refreshAccessToken() {
                    if let newToken = accessToken, !newToken.isEmpty {
                        do {
                            let status = try await APIService.shared.validateAuth(token: newToken)
                            if status.state == "paid" {
                                currentState = .paid
                                print("[AppState] Token refreshed, state = .paid")
                                return
                            }
                        } catch { /* fall through */ }
                    } else {
                        // Token refresh claimed success but token not in Keychain — retry once
                        print("[AppState] Token refresh succeeded but token not saved, retrying...")
                        if await APIService.shared.refreshAccessToken(), let retryToken = accessToken, !retryToken.isEmpty {
                            do {
                                let status = try await APIService.shared.validateAuth(token: retryToken)
                                if status.state == "paid" {
                                    currentState = .paid
                                    print("[AppState] Token refreshed on retry, state = .paid")
                                    return
                                }
                            } catch { /* fall through */ }
                        }
                    }
                }
                clearTokens()
                print("[AppState] Token validation failed: \(error.localizedDescription)")
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
                print("[AppState] Device status: \(status.queriesRemaining) queries remaining, state = .freeActive")
            } else {
                // Check if referral reward is active before marking as exhausted
                await checkReferralReward()
                if currentState != .referralActive {
                    currentState = .freeExhausted
                    print("[AppState] Device status: 0 queries remaining, state = .freeExhausted")
                } else {
                    print("[AppState] Device status: referral reward active, state = .referralActive")
                }
            }
        } catch {
            // #19 — Backend unreachable: do NOT grant free queries offline
            isOffline = true
            currentState = .anonymous
            queriesRemaining = 0
            print("[AppState] Backend unreachable, state = .anonymous (offline)")
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
            print("[AppState] Ignoring unknown state: \(state)")
        }
        
        print("[AppState] Updated after query: \(queriesRemaining) remaining, state = \(currentState)")
    }
    
    @MainActor
    func setStateToPaid(jwt: String) {
        saveJWT(jwt)
        currentState = .paid
        print("[AppState] State set to .paid")
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
        print("[AppState] Signed out, state = .freeExhausted")
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
                    return
                }
                // Also try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let expires = formatter.date(from: expiresStr), expires > Date() {
                    referralRewardActive = true
                    currentState = .referralActive
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
