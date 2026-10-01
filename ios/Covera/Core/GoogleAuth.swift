import AuthenticationServices
import CryptoKit
import Security
import UIKit

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Google sign-in isn’t set up yet.")
        case .cancelled: nil
        case .failed: String(localized: "Google sign-in didn’t complete. Try again.")
        }
    }
}

/// "Continue with Google" without a third-party SDK: the standard OAuth flow
/// for native apps (authorization code + PKCE) in Apple's own secure browser
/// sheet. The app never sees the Google password; it receives an ID token and
/// hands it to the Clausa server, which verifies it with Google.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// The iOS OAuth client ID, set as `COVERA_GOOGLE_CLIENT_ID` in project.yml.
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CoveraGoogleClientID") as? String,
              value.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return value
    }

    static var isConfigured: Bool { clientID != nil }

    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> String {
        guard let clientID = Self.clientID else { throw GoogleAuthError.notConfigured }

        // Google's redirect scheme for iOS clients is the client ID reversed.
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomURLSafe(bytes: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = Self.randomURLSafe(bytes: 16)

        var authorize = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authorize.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorize.url!, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleAuthError.failed)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() { continuation.resume(throwing: GoogleAuthError.failed) }
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // A mismatched state means this callback did not come from the request
        // we just made.
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.failed
        }

        var exchange = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        exchange.httpMethod = "POST"
        exchange.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        exchange.httpBody = Self.formEncoded([
            ("code", code),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier),
        ])

        let (data, response) = try await URLSession.shared.data(for: exchange)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw GoogleAuthError.failed
        }
        return idToken
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func formEncoded(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
