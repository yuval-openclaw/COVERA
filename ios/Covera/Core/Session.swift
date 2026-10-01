import Foundation
import Security

/// The signed-in session.
///
/// Only the opaque session token is kept on the device — never the password —
/// in the Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: it does
/// not sync to iCloud and does not travel in an unencrypted backup. On a device
/// holding someone's medical history that matters more than the convenience of
/// a restore.
actor Session {
    static let shared = Session()

    private let account = "covera.session"
    private let service = "com.covera.app"

    var token: String? { readKeychain() }

    /// Readable without awaiting, so the app can choose its first screen at launch.
    nonisolated var hasToken: Bool { readKeychain() != nil }

    func signIn(token: String) throws {
        try writeKeychain(token)
    }

    func signOut() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Keychain

    // Nonisolated: these touch only immutable constants and the Keychain.
    nonisolated private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    nonisolated private func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private func writeKeychain(_ value: String) throws {
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Whether someone is signed in, observable by the UI. Flips to signed out
/// when the server rejects the session, wherever that happens.
@MainActor
@Observable
final class AuthState {
    static let shared = AuthState()

    private(set) var isSignedIn: Bool
    /// Whether the signed-in account has accepted the current agreements.
    /// Nil until the server has been asked; reset on every sign-in and
    /// sign-out, because agreement belongs to the account, not the device.
    private(set) var hasAgreed: Bool?

    private init() {
        isSignedIn = Session.shared.hasToken
    }

    func didSignIn() { isSignedIn = true; hasAgreed = nil }
    func didSignOut() { isSignedIn = false; hasAgreed = nil }
    func didAgree() { hasAgreed = true }

    /// Asks the server whether this account has agreed to `version`.
    func refreshAgreement(version: String) async {
        do {
            hasAgreed = try await APIClient.shared.consentVersion() == version
        } catch {
            // Offline or signed out: the agreement screen will ask, and
            // recording the answer will surface the real problem.
            hasAgreed = false
        }
    }
}
