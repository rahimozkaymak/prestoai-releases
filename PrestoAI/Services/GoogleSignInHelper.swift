import AppKit
import Foundation

/// Handles Google Sign-In via OAuth 2.0 authorization code flow.
/// Uses a local HTTP server to receive the callback — no Google SDK needed.
///
/// Prerequisites:
/// 1. Create OAuth 2.0 credentials at https://console.cloud.google.com/apis/credentials
/// 2. Set the redirect URI to http://127.0.0.1:9004/callback
/// 3. Set the client ID and secret below (secret should be moved to backend in production)
enum GoogleSignInHelper {

    // TODO: Replace with your actual Google OAuth credentials.
    // The client secret should ideally live on your backend — the macOS app
    // sends the auth code to your backend, which exchanges it for tokens.
    private static let clientID = "REPLACE_WITH_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    private static let redirectURI = "http://127.0.0.1:9004/callback"
    private static let callbackPort: UInt16 = 9004

    enum GoogleAuthError: LocalizedError {
        case cancelled
        case noAuthCode
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Sign-in was cancelled."
            case .noAuthCode: return "No authorization code received from Google."
            case .serverError(let msg): return msg
            }
        }
    }

    /// Opens Google OAuth in the default browser, waits for the callback,
    /// then sends the auth code to our backend which exchanges it for a JWT.
    @MainActor
    static func signIn() async throws -> String {
        let authCode = try await getAuthorizationCode()
        let jwt = try await APIService.shared.googleSignIn(authCode: authCode, redirectURI: redirectURI)
        return jwt
    }

    // MARK: - OAuth Flow

    /// Starts a temporary local HTTP server, opens the Google consent screen,
    /// and returns the authorization code from the redirect.
    private static func getAuthorizationCode() async throws -> String {
        // Build the Google OAuth URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authURL = components.url else {
            throw GoogleAuthError.serverError("Failed to build Google auth URL")
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Start local callback server
            let server = LocalCallbackServer(port: callbackPort) { params in
                if let error = params["error"] {
                    if error == "access_denied" {
                        continuation.resume(throwing: GoogleAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: GoogleAuthError.serverError(error))
                    }
                } else if let code = params["code"] {
                    continuation.resume(returning: code)
                } else {
                    continuation.resume(throwing: GoogleAuthError.noAuthCode)
                }
            }
            server.start()

            // Open browser
            NSWorkspace.shared.open(authURL)
        }
    }
}

// MARK: - Minimal Local HTTP Server for OAuth Callback

/// A single-use HTTP server that listens on localhost for the OAuth redirect.
/// Automatically stops after receiving one request.
private final class LocalCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private let onCallback: ([String: String]) -> Void
    private var serverSocket: Int32 = -1

    init(port: UInt16, onCallback: @escaping ([String: String]) -> Void) {
        self.port = port
        self.onCallback = onCallback
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard serverSocket >= 0 else { return }

            var yes: Int32 = 1
            setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else { close(serverSocket); return }
            listen(serverSocket, 1)

            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else { close(serverSocket); return }

            // Read the HTTP request
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(client, &buffer, buffer.count, 0)
            let requestStr = bytesRead > 0 ? String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? "" : ""

            // Parse query params from "GET /callback?code=...&... HTTP/1.1"
            var params: [String: String] = [:]
            if let firstLine = requestStr.components(separatedBy: "\r\n").first,
               let urlPart = firstLine.components(separatedBy: " ").dropFirst().first,
               let comps = URLComponents(string: urlPart) {
                for item in comps.queryItems ?? [] {
                    params[item.name] = item.value
                }
            }

            // Send a response to the browser
            let html = """
            <html><body style="font-family:-apple-system,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#111;color:#fff">
            <div style="text-align:center"><h1>You're signed in!</h1><p>You can close this tab and return to Presto AI.</p></div>
            </body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            _ = response.withCString { send(client, $0, Int(strlen($0)), 0) }

            close(client)
            close(serverSocket)

            self.onCallback(params)
        }
    }
}
