import Foundation
import LocalAuthentication
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

/// Face ID / Touch ID gate in front of stored documents.
@MainActor
@Observable
final class AppLock {
    enum State: Equatable {
        case locked
        case unlocked
        case unavailable(String)
    }

    private(set) var state: State = .locked
    /// Ask on the next return to the foreground. Set whenever the lock closes
    /// and cleared by any attempt, so cancelling the prompt — which itself
    /// makes the app inactive and active again — cannot summon it in a loop.
    private(set) var promptOnActive = true
    private var evaluating = false

    /// Whether the device can authenticate at all. If it cannot — no passcode
    /// set — we say so rather than silently leaving documents open.
    var canEvaluate: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func unlock() async {
        promptOnActive = false
        guard !evaluating else { return }
        evaluating = true
        defer { evaluating = false }
        #if DEBUG
        // Screenshots and design review only. `-CoveraDemo` shows fictional
        // sample data, so there is nothing behind the lock to protect.
        // Compiled out of release builds.
        // `-CoveraDemoLocked` keeps the real lock over the sample data, so the
        // gate itself can be exercised on the simulator without an account.
        if PreviewData.isDemo && !ProcessInfo.processInfo.arguments.contains("-CoveraDemoLocked") {
            state = .unlocked
            return
        }
        #endif

        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use passcode")

        var error: NSError?
        var available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #if DEBUG
        // A device with neither passcode nor biometrics, which a simulator with
        // a passcode set cannot otherwise show.
        if ProcessInfo.processInfo.arguments.contains("-CoveraNoDeviceLock") { available = false }
        #endif
        guard available else {
            // Falling back to open access would be the wrong default here, but
            // so would locking someone out of their own policies during a
            // medical event. We surface the situation and let them proceed.
            state = .unavailable(
                String(localized: "This device has no passcode or biometric lock, so Covera cannot lock your documents.")
            )
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock your insurance documents")
            )
            state = ok ? .unlocked : .locked
        } catch {
            state = .locked
        }
    }

    /// A fresh sign-in has just proved who this is; asking for Face ID again a
    /// second later would only add a step.
    func grantAfterSignIn() {
        state = .unlocked
    }

    /// The device has no passcode and no biometrics, so nothing on it can prove
    /// who is holding it. The lock screen says so every time the app comes to
    /// the foreground, and the person may continue: refusing would shut someone
    /// out of their own policies during a medical event, while protecting
    /// nothing the unlocked phone itself does not already expose.
    func continueWithoutLock() {
        guard case .unavailable = state else { return }
        state = .unlocked
    }

    func lock() {
        state = .locked
        promptOnActive = true
    }
}
