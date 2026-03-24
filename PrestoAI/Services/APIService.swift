import Foundation
import AppKit

// TODO: Implement certificate pinning for production

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
}

struct QueryResponse: Codable {
    let text: String
    let tokensUsed: Int
}

struct UserProfile: Codable {
    let email: String
    let referralCode: String
    let referralCount: Int
    let subscriptionStatus: String
    let trialEndsAt: String?
}

struct DeviceStatus: Codable {
    let queriesRemaining: Int
    let totalFreeQueries: Int?
    let state: String
}

struct AuthStatus: Codable {
    let state: String
    let token: String?
    let email: String?
}

struct AnalyzeResponse: Codable {
    let result: String?
    let queriesRemaining: Int
    let state: String
}

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case subscriptionExpired
    case rateLimited
    case freeExhausted
    case noAccess
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Please log in to continue."
        case .subscriptionExpired: return "Your subscription has expired. Renew at presto.ai/account"
        case .rateLimited: return "Too many requests. Please wait a moment."
        case .freeExhausted: return "Free queries exhausted. Please subscribe."
        case .noAccess: return "Free queries exhausted. Subscribe or refer friends to continue."
        case .serverError(let msg): return "Server error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

class APIService {
    static let shared = APIService()
    
    // MARK: - Production base URL (override via UserDefaults for dev)
    let baseURL: String
    
    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: "apiBaseURL")
            ?? "https://prestoai-backend-production.up.railway.app"
        print("[API] Base URL: \(self.baseURL)")
    }
    
    // MARK: - Token access (single source: AppStateManager)
    
    private var accessToken: String? { AppStateManager.shared.accessToken }
    private var refreshToken: String? { AppStateManager.shared.refreshToken }
    
    // MARK: - Auth
    
    func login(email: String, password: String) async throws -> (profile: UserProfile, jwt: String) {
        print("[API] Logging in: \(email)")
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await post(endpoint: "/api/auth/login", body: body, authenticated: false)

        let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
        await AppStateManager.shared.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
        print("[API] Login successful, tokens saved")

        let profile = try await getProfileWithRetry()
        return (profile, tokens.accessToken)
    }

    func register(email: String, password: String, referralCode: String? = nil) async throws -> (profile: UserProfile, jwt: String) {
        print("[API] Registering: \(email)")
        var body: [String: Any] = [
            "email": email,
            "password": password,
            "device_id": AppStateManager.shared.deviceID,
        ]
        if let code = referralCode { body["referral_code"] = code }

        let data = try await post(endpoint: "/api/auth/register", body: body, authenticated: false)

        let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
        await AppStateManager.shared.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
        print("[API] Registration successful, tokens saved")

        let profile = try await getProfileWithRetry()
        return (profile, tokens.accessToken)
    }

    func redeemPromoCode(code: String, token: String) async throws -> String {
        print("[API] Redeeming code: \(code)")
        let urlStr = baseURL + "/api/promo/redeem"
        guard let url = URL(string: urlStr) else {
            throw APIError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }
        if http.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("Promo redemption failed (\(http.statusCode))")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String {
            return message
        }
        return "Promo code redeemed!"
    }

    private func getProfileWithRetry(maxAttempts: Int = 3) async throws -> UserProfile {
        for attempt in 1...maxAttempts {
            do {
                return try await getProfile()
            } catch {
                if attempt < maxAttempts {
                    print("[API] Profile fetch attempt \(attempt) failed, retrying in \(attempt)s...")
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                } else {
                    throw error
                }
            }
        }
        throw APIError.networkError("Profile fetch failed after \(maxAttempts) attempts")
    }
    
    func logout() {
        Task { @MainActor in AppStateManager.shared.signOut() }
        print("[API] Logged out")
    }
    
    var isLoggedIn: Bool { accessToken != nil }
    
    // MARK: - Token Refresh
    
    /// Attempt to refresh the access token using the stored refresh token.
    /// Returns true if refresh succeeded, false otherwise.
    func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken else { return false }
        
        print("[API] Attempting token refresh...")
        do {
            let body: [String: Any] = ["refreshToken": refresh]
            let data = try await post(endpoint: "/api/auth/refresh", body: body, authenticated: false)
            let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
            await AppStateManager.shared.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            print("[API] Token refresh successful")
            return true
        } catch {
            print("[API] Token refresh failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Core Analyze (streaming)

    func sendScreenshot(_ base64Image: String, prompt: String? = nil,
                        model: String? = nil,
                        skipCompression: Bool = false,
                        onChunk: @escaping (String) -> Void,
                        onComplete: @escaping (Int, String) -> Void,
                        onError: @escaping (Error) -> Void = { _ in }) {
        let p = prompt ?? UserDefaults.standard.string(forKey: "defaultPrompt")
            ?? "Help me solve this problem. Be clear and concise. Use proper mathematical notation and LaTeX formatting for any math expressions."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let (compressed, mediaType) = skipCompression
                ? (base64Image, "image/jpeg")
                : ImageCompressor.compress(base64Image)

            let deviceID = AppStateManager.shared.deviceID
            var bodyDict: [String: Any] = [
                "image": compressed,
                "prompt": p,
                "media_type": mediaType,
                "device_id": deviceID
            ]
            if let model = model {
                bodyDict["model"] = model
            }

            guard let body = try? JSONSerialization.data(withJSONObject: bodyDict),
                  let url = URL(string: self.baseURL + "/api/analyze") else {
                DispatchQueue.main.async { onError(APIError.networkError("Invalid URL")) }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
            
            if let token = self.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = body
            request.timeoutInterval = 300  // 5 minutes: covers large image upload + Anthropic stream

            let delegate = SSEStreamDelegate(onChunk: onChunk, onComplete: onComplete, onError: onError)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.setSession(session)
            session.dataTask(with: request).resume()
        }
    }
    
    // MARK: - Device & Auth Status
    
    func checkDeviceStatus(deviceID: String) async throws -> DeviceStatus {
        let urlStr = baseURL + "/api/device/status?device_id=\(deviceID)"
        print("[API] GET \(urlStr)")
        guard let url = URL(string: urlStr) else {
            throw APIError.networkError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response, data: data)
        return try JSONDecoder().decode(DeviceStatus.self, from: data)
    }
    
    func validateAuth(token: String) async throws -> AuthStatus {
        let data = try await get(endpoint: "/api/auth/status", token: token)
        return try JSONDecoder().decode(AuthStatus.self, from: data)
    }
    
    // FIX #9: Use URLComponents to properly encode query parameters
    func getCheckoutURL(email: String, deviceID: String) async throws -> String {
        guard var components = URLComponents(string: baseURL + "/api/billing/checkout-url") else {
            throw APIError.networkError("Invalid URL")
        }
        components.queryItems = [
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "device_id", value: deviceID)
        ]
        guard let url = components.url else {
            throw APIError.networkError("Invalid URL")
        }
        
        print("[API] GET \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response, data: data)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let checkoutURL = json["checkout_url"] as? String else {
            throw APIError.serverError("Invalid checkout URL response")
        }
        
        return checkoutURL
    }
    
    // MARK: - Device Referral System

    struct ReferralCodeResponse {
        let code: String
        let shareURL: String
    }

    func getPaywallInfo(deviceID: String) async throws -> PaywallInfo {
        guard var components = URLComponents(string: baseURL + "/api/referral/paywall") else {
            throw APIError.networkError("Invalid URL")
        }
        components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        guard let url = components.url else { throw APIError.networkError("Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverError("Invalid paywall response")
        }

        let canUseReferral = json["can_use_referral"] as? Bool ?? false
        let referralCode = json["referral_code"] as? String
        let status = json["referral_status"] as? [String: Any] ?? [:]
        let qualifiedCount = status["qualified_count"] as? Int ?? 0
        let needed = status["needed"] as? Int ?? 3
        let subscribePrice = json["subscribe_price"] as? String ?? "$9.99/mo"
        let checkoutURL = json["checkout_url"] as? String ?? ""
        let rewardExpiresAt = json["reward_expires_at"] as? String

        return PaywallInfo(
            canUseReferral: canUseReferral,
            referralCode: referralCode,
            qualifiedCount: qualifiedCount,
            needed: needed,
            subscribePrice: subscribePrice,
            checkoutURL: checkoutURL,
            rewardExpiresAt: rewardExpiresAt
        )
    }

    func createReferralCode(deviceID: String) async throws -> ReferralCodeResponse {
        let body: [String: Any] = ["device_id": deviceID]
        let data = try await post(endpoint: "/api/referral/code", body: body, authenticated: false)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String,
              let shareURL = json["share_url"] as? String else {
            throw APIError.serverError("Invalid referral code response")
        }

        return ReferralCodeResponse(code: code, shareURL: shareURL)
    }

    func claimReferralCode(deviceID: String, code: String) async throws {
        let body: [String: Any] = ["device_id": deviceID, "code": code]
        _ = try await post(endpoint: "/api/referral/claim", body: body, authenticated: false)
    }

    // MARK: - Password Reset & Logout

    func requestPasswordReset(email: String) async throws {
        let body: [String: Any] = ["email": email]
        _ = try await post(endpoint: "/api/auth/request-reset", body: body, authenticated: false)
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        let body: [String: Any] = ["email": email, "code": code, "newPassword": newPassword]
        _ = try await post(endpoint: "/api/auth/reset-password", body: body, authenticated: false)
    }

    func logout(refreshToken: String) async {
        let body: [String: Any] = ["refreshToken": refreshToken]
        _ = try? await post(endpoint: "/api/auth/logout", body: body, authenticated: false)
    }

    // MARK: - Profile & Referral

    func getProfile() async throws -> UserProfile {
        let data = try await get(endpoint: "/api/user/profile")
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }
    
    func getReferralCode() async throws -> String {
        let profile = try await getProfile()
        return profile.referralCode
    }
    
    // MARK: - Study Mode

    func analyzeStudyCapture(context: [String: Any]) async throws -> StudySuggestion? {
        let data = try await post(endpoint: "/api/v1/study/analyze", body: context)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return nil
        }

        if action == "none" { return nil }

        guard let text = json["suggestion_text"] as? String,
              let type = json["suggestion_type"] as? String,
              let confidence = json["confidence"] as? String,
              let followUp = json["follow_up_prompt"] as? String else {
            return nil
        }

        // Only show medium/high confidence suggestions
        guard confidence == "medium" || confidence == "high" else { return nil }

        return StudySuggestion(
            captureId: json["capture_id"] as? String ?? UUID().uuidString,
            suggestionText: text,
            suggestionType: type,
            confidence: confidence,
            followUpPrompt: followUp
        )
    }

    func reportStudySession(body: [String: Any]) async throws {
        _ = try await post(endpoint: "/api/v1/study/session", body: body)
    }

    func postFeedback(body: [String: Any]) async throws -> Data {
        try await post(endpoint: "/api/feedback", body: body, authenticated: false)
    }

    // MARK: - HTTP Helpers
    
    private func get(endpoint: String, token: String? = nil, retried: Bool = false) async throws -> Data {
        let urlStr = baseURL + endpoint
        print("[API] GET \(urlStr)")
        guard let url = URL(string: urlStr) else {
            throw APIError.networkError("Invalid URL: \(urlStr)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token ?? accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-refresh on 401
        if let http = response as? HTTPURLResponse, http.statusCode == 401, token == nil {
            if await refreshAccessToken() {
                return try await get(endpoint: endpoint) // retry with new token
            }
        }

        // Retry once on 5xx server errors
        if let http = response as? HTTPURLResponse, (500...599).contains(http.statusCode), !retried {
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await get(endpoint: endpoint, token: token, retried: true)
        }

        try handleResponse(response, data: data)
        return data
    }
    
    private func post(endpoint: String, body: [String: Any], authenticated: Bool = true, retried: Bool = false) async throws -> Data {
        let urlStr = baseURL + endpoint
        print("[API] POST \(urlStr)")
        guard let url = URL(string: urlStr) else {
            throw APIError.networkError("Invalid URL: \(urlStr)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if authenticated, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // Auto-refresh on 401 (only for authenticated requests)
        if authenticated, let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if await refreshAccessToken() {
                return try await post(endpoint: endpoint, body: body, authenticated: true)
            }
        }

        // Retry once on 5xx server errors
        if let http = response as? HTTPURLResponse, (500...599).contains(http.statusCode), !retried {
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await post(endpoint: endpoint, body: body, authenticated: authenticated, retried: true)
        }

        try handleResponse(response, data: data)
        return data
    }
    
    // MARK: - Auto-Solve

    struct AutoSolveAnswer {
        let questionText: String
        let answerText: String
        let yPositionPercent: Double  // 0.0 = top, 1.0 = bottom
    }

    struct AutoSolveResponse {
        let isHomework: Bool
        let subject: String?
        let promptText: String?
        let answers: [AutoSolveAnswer]
    }

    func analyzeAutoSolve(image: String, mediaType: String, mode: String,
                          sessionId: String, deviceId: String) async throws -> AutoSolveResponse {
        let body: [String: Any] = [
            "image": image,
            "media_type": mediaType,
            "mode": mode,
            "session_id": sessionId,
            "device_id": deviceId
        ]

        let data = try await post(endpoint: "/api/v1/study/auto-solve", body: body)
        print("[AutoSolve] Response body: \(String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? "nil")")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.serverError("Invalid auto-solve response")
        }

        let isHomework = json["is_homework"] as? Bool ?? false
        let subject = json["subject"] as? String
        let promptText = json["prompt_text"] as? String

        var answers: [AutoSolveAnswer] = []
        if let answersArray = json["answers"] as? [[String: Any]] {
            for item in answersArray {
                guard let questionText = item["question_text"] as? String,
                      let answerText = item["answer_text"] as? String,
                      let yPos = item["y_position_percent"] as? Double else { continue }
                answers.append(AutoSolveAnswer(
                    questionText: questionText,
                    answerText: answerText,
                    yPositionPercent: yPos
                ))
            }
        }

        return AutoSolveResponse(
            isHomework: isHomework,
            subject: subject,
            promptText: promptText,
            answers: answers
        )
    }

    private func handleResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        
        print("[API] Response status: \(httpResponse.statusCode)")
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            if let data = data, let body = String(data: data, encoding: .utf8) {
                print("[API] Error body: \(body)")
            }
        }
        
        switch httpResponse.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 403:
            // Differentiate between subscription expired, free exhausted, and no_access
            if let data = data, let body = String(data: data, encoding: .utf8) {
                if body.contains("Free queries exhausted") {
                    throw APIError.freeExhausted
                }
                if body.contains("no_access") {
                    throw APIError.noAccess
                }
            }
            throw APIError.subscriptionExpired
        case 429: throw APIError.rateLimited
        default:
            // Extract "detail" message from backend JSON response (e.g. "Email already registered")
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("Status \(httpResponse.statusCode)")
        }
    }
}


// MARK: - Image Compression (extracted helper)

enum ImageCompressor {
    
    /// Compress a base64 PNG screenshot to JPEG, resizing if needed.
    /// Returns (base64String, mediaType).
    static func compress(_ base64: String) -> (String, String) {
        guard let data = Data(base64Encoded: base64),
              let nsImage = NSImage(data: data) else {
            print("[Image] Decode failed, using original")
            return (base64, "image/png")
        }
        
        // Resize to fit within 1568px on longest side, JPEG at 80% quality
        if let result = resizeAndEncode(nsImage, maxSide: 1568, quality: 0.80) {
            print("[Image] Compressed: \(base64.count) → \(result.count) chars")
            return (result, "image/jpeg")
        }

        // Fallback: resize to PNG at 1568px instead of sending original full-size
        if let pngResult = resizeAndEncodePNG(nsImage, maxSide: 1568) {
            print("[Image] JPEG failed, using resized PNG: \(base64.count) → \(pngResult.count) chars")
            return (pngResult, "image/png")
        }

        print("[Image] All compression failed, using original")
        return (base64, "image/png")
    }
    
    private static func resizeAndEncode(_ image: NSImage, maxSide: CGFloat, quality: CGFloat) -> String? {
        var size = image.size
        if size.width > maxSide || size.height > maxSide {
            let scale = maxSide / max(size.width, size.height)
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        guard let resizedCG = ctx.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: resizedCG)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return nil }

        return jpeg.base64EncodedString()
    }

    private static func resizeAndEncodePNG(_ image: NSImage, maxSide: CGFloat) -> String? {
        var size = image.size
        if size.width > maxSide || size.height > maxSide {
            let scale = maxSide / max(size.width, size.height)
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let resizedCG = ctx.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: resizedCG)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        return png.base64EncodedString()
    }
}


// MARK: - SSE Stream Delegate

private class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    let onChunk: (String) -> Void
    let onComplete: (Int, String) -> Void
    let onError: (Error) -> Void
    private var buffer = ""
    private var session: URLSession?
    // FIX #4: Use optionals instead of bogus defaults to detect missing state data
    private var lastQueriesRemaining: Int?
    private var lastState: String?
    private var didReportError = false

    init(onChunk: @escaping (String) -> Void, onComplete: @escaping (Int, String) -> Void, onError: @escaping (Error) -> Void) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func setSession(_ session: URLSession) { self.session = session }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.allow); return }
        switch http.statusCode {
        case 200...299:
            completionHandler(.allow)
        case 401:
            didReportError = true
            DispatchQueue.main.async { self.onError(APIError.unauthorized) }
            completionHandler(.cancel)
        case 403:
            didReportError = true
            DispatchQueue.main.async { self.onError(APIError.noAccess) }
            completionHandler(.cancel)
        case 429:
            didReportError = true
            DispatchQueue.main.async { self.onError(APIError.rateLimited) }
            completionHandler(.cancel)
        default:
            didReportError = true
            DispatchQueue.main.async { self.onError(APIError.serverError("Status \(http.statusCode)")) }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""
        for line in lines.dropLast() {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { continue }
            guard let jsonData = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
            if let delta = obj["delta"] as? String {
                DispatchQueue.main.async { self.onChunk(delta) }
            } else if let errorMsg = obj["error"] as? String {
                didReportError = true
                DispatchQueue.main.async { self.onError(APIError.serverError(errorMsg)) }
            }
            
            // Track queries_remaining and state for completion callback
            if let qr = obj["queries_remaining"] as? Int {
                lastQueriesRemaining = qr
            }
            if let st = obj["state"] as? String {
                lastState = st
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.session?.finishTasksAndInvalidate()
        self.session = nil
        
        if let error = error as NSError? {
            if error.code != NSURLErrorCancelled {
                DispatchQueue.main.async { self.onError(APIError.networkError(error.localizedDescription)) }
            }
        } else {
            // FIX #4: Only call onComplete if we actually received valid state data.
            // If the state was never set in the stream, don't send bogus 0/"unknown"
            // which would lock free users out.
            if let qr = lastQueriesRemaining, let st = lastState {
                DispatchQueue.main.async { self.onComplete(qr, st) }
            } else if !didReportError {
                print("[SSE] Stream completed but no state data received — backend may not be running")
                DispatchQueue.main.async { self.onError(APIError.networkError("No response received. Is the backend running?")) }
            }
        }
    }
}
