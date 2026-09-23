import AuthenticationServices
import CryptoKit
import Foundation

enum AppleAuthError: LocalizedError {
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled: nil
        case .failed: String(localized: "Apple sign-in didn't complete. Try again.")
        }
    }
}

/// Sign in with Apple, which App Review requires of any app that also offers
/// Google sign-in (Guideline 4.8) — and which suits this app: Apple's private
/// relay lets someone keep a library of their insurance policies without ever
/// handing over a real address.
///
/// The button itself is Apple's (`SignInWithAppleButton`), so there is no OAuth
/// flow to run here. What is left is the nonce: the app makes a random string,
/// gives Apple its hash, and sends the original to our server with the token.
/// The server hashes it again and compares, so a token captured from some other
/// sign-in cannot be replayed into this one.
enum AppleAuth {
    /// A fresh nonce per sign-in attempt. Keep it until the token comes back.
    static func newNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // Never a plain random: this is what makes the token non-replayable.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // The system RNG failing is not something to paper over with a
            // weaker one; UUIDs are still system-random.
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
    }

    /// What Apple is given, and what the identity token comes back carrying.
    static func hashed(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Only the address is asked for. The full name is not needed to read
    /// someone their own policy, and the Privacy Policy says we collect what
    /// the service needs.
    static func prepare(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.email]
        request.nonce = hashed(nonce)
    }

    static func identityToken(from result: Result<ASAuthorization, Error>) throws -> String {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let data = credential.identityToken,
                let token = String(data: data, encoding: .utf8)
            else { throw AppleAuthError.failed }
            return token
        case .failure(let error):
            let code = (error as? ASAuthorizationError)?.code
            throw code == .canceled || code == .unknown ? AppleAuthError.cancelled : AppleAuthError.failed
        }
    }
}
