import CommonCrypto
import Foundation
import Security

/// The code in front of the Policies tab.
///
/// Six digits the person chooses, asked for whenever they come back to their
/// policies after the app has been in the background. It replaced an app-wide
/// Face ID lock by the owner's decision (2026-10-01); the rest of the app opens
/// without it.
///
/// Only a salted PBKDF2 hash is kept, in the Keychain, on this device only.
/// Forgetting the code costs a sign-in, never data: signing out clears it (the
/// policies themselves live on the server), and so do ten wrong tries in a row.
@MainActor
@Observable
final class PolicyLock {
    enum State: Equatable { case needsCode, locked, unlocked }
    enum Attempt: Equatable { case accepted, rejected(attemptsLeft: Int), exhausted }

    static let length = 6
    static let maxAttempts = 10

    private(set) var state: State
    /// Demo launches show fictional data and skip the code, unless
    /// `-CoveraDemoLocked` asks for the real thing.
    private let exempt: Bool

    init() {
        #if DEBUG
        exempt = PreviewData.isDemo && !ProcessInfo.processInfo.arguments.contains("-CoveraDemoLocked")
        #else
        exempt = false
        #endif
        state = exempt ? .unlocked : (Self.readStored() == nil ? .needsCode : .locked)
    }

    /// Stores a new code and opens the policies: whoever typed it twice knows it.
    func set(code: String) throws {
        precondition(code.count == Self.length && code.allSatisfy(\.isNumber))
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        try Self.writeStored(salt + Self.derive(code, salt: salt))
        failures = 0
        state = .unlocked
    }

    func attempt(_ code: String) -> Attempt {
        guard let stored = Self.readStored(), stored.count == 48 else {
            state = .needsCode
            return .rejected(attemptsLeft: Self.maxAttempts)
        }
        let salt = Data(stored.prefix(16)), hash = Data(stored.suffix(32))
        if Self.constantTimeEqual(Self.derive(code, salt: salt), hash) {
            failures = 0
            state = .unlocked
            return .accepted
        }
        failures += 1
        return failures >= Self.maxAttempts ? .exhausted : .rejected(attemptsLeft: Self.maxAttempts - failures)
    }

    /// Closes the policies again, if there is a code to open them with.
    func lock() {
        guard !exempt, state == .unlocked, Self.readStored() != nil else { return }
        state = .locked
    }

    /// Forgets the code. Called on every sign-out, which is also how a
    /// forgotten code is replaced: sign back in and choose a new one.
    func reset() {
        SecItemDelete(Self.query as CFDictionary)
        SecItemDelete(Self.failuresQuery as CFDictionary)
        state = exempt ? .unlocked : .needsCode
    }

    // MARK: - Storage

    /// Consecutive wrong tries. Kept in the Keychain beside the code, not in
    /// UserDefaults: deleting and reinstalling the app clears UserDefaults but
    /// not the Keychain, so a counter there would hand out ten more tries while
    /// the code — and the session — survived.
    private var failures: Int {
        get { Self.read(Self.failuresQuery).flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0 }
        set { try? Self.write(Data(String(newValue).utf8), to: Self.failuresQuery) }
    }

    private static let query = item("covera.policy-code")
    private static let failuresQuery = item("covera.policy-code-failures")

    private static func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.covera.app",
            kSecAttrAccount as String: account,
        ]
    }

    private static func readStored() -> Data? { read(query) }
    private static func writeStored(_ data: Data) throws { try write(data, to: query) }

    private static func read(_ base: [String: Any]) -> Data? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func write(_ data: Data, to base: [String: Any]) throws {
        SecItemDelete(base as CFDictionary)
        var q = base
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private static func derive(_ code: String, salt: Data) -> Data {
        var out = Data(count: 32)
        let length = code.utf8.count
        out.withUnsafeMutableBytes { key in
            salt.withUnsafeBytes { s in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), code, length,
                                         s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000,
                                         key.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return out
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
