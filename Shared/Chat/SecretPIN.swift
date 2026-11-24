import Foundation
import CommonCrypto

/// Where PIN data is kept. Production: Keychain. Tests: memory.
protocol SecretPINStorage: AnyObject {
    func load(_ key: String) -> Data?
    func save(_ data: Data, _ key: String)
    func remove(_ key: String)
}

final class KeychainPINStorage: SecretPINStorage {
    func load(_ key: String) -> Data? { SecureStore.get(key) }
    func save(_ data: Data, _ key: String) { SecureStore.set(data, for: key) }
    func remove(_ key: String) { SecureStore.delete(key) }
}

final class MemoryPINStorage: SecretPINStorage {
    var items: [String: Data] = [:]
    func load(_ key: String) -> Data? { items[key] }
    func save(_ data: Data, _ key: String) { items[key] = data }
    func remove(_ key: String) { items[key] = nil }
}

/// The local Secret Chat unlock PIN. It is a local access control only — never sent to the server,
/// never used as an encryption key, never inserted into the host app.
/// Stored as PBKDF2-HMAC-SHA256 (per-device random salt, 210 000 iterations) in the Keychain.
/// (PBKDF2 is not memory-hard; Argon2/scrypt would need a third-party library. The Keychain item is
/// device-only and the retry limits below are the main brute-force protection.)
final class SecretPIN {
    struct Verifier: Codable { let salt: Data; let hash: Data; let iterations: Int; let length: Int }
    struct State: Codable { var failures: Int = 0; var lockedUntil: Date? = nil }

    enum Result: Equatable { case ok, wrong(remainingBeforeLock: Int), locked(until: Date), notSet }

    static let shared = SecretPIN(storage: KeychainPINStorage())
    static let defaultIterations = 210_000

    let storage: SecretPINStorage
    var now: () -> Date = Date.init
    let iterations: Int

    init(storage: SecretPINStorage, iterations: Int = SecretPIN.defaultIterations) {
        self.storage = storage
        self.iterations = iterations
    }

    var isSet: Bool { verifier != nil }
    var length: Int? { verifier?.length }

    private var verifier: Verifier? {
        storage.load(SecureStore.Keys.pin).flatMap { try? JSONDecoder().decode(Verifier.self, from: $0) }
    }
    var state: State {
        get { storage.load(SecureStore.Keys.pinState).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State() }
        set { if let d = try? JSONEncoder().encode(newValue) { storage.save(d, SecureStore.Keys.pinState) } }
    }

    static func isAcceptable(_ pin: String) -> Bool {
        guard (4...8).contains(pin.count), pin.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let weak: Set<String> = ["0000", "1111", "1234", "4321", "123456", "654321", "000000", "111111", "12345678"]
        if weak.contains(pin) { return false }
        if Set(pin).count == 1 { return false }
        return true
    }

    /// Sets (or replaces) the PIN. Changing requires `current` to verify first.
    @discardableResult
    func set(_ pin: String, current: String? = nil) -> Bool {
        guard SecretPIN.isAcceptable(pin) else { return false }
        if isSet {
            guard let c = current, verify(c) == .ok else { return false }
        }
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let v = Verifier(salt: salt, hash: SecretPIN.derive(pin, salt: salt, iterations: iterations), iterations: iterations, length: pin.count)
        guard let d = try? JSONEncoder().encode(v) else { return false }
        storage.save(d, SecureStore.Keys.pin)
        state = State()
        return true
    }

    func remove() {
        storage.remove(SecureStore.Keys.pin)
        storage.remove(SecureStore.Keys.pinState)
    }

    /// Delay after `failures` wrong attempts: 4 free tries, then 30 s, 1 min, 5 min, 15 min, then 1 h each.
    static func lockDuration(afterFailures n: Int) -> TimeInterval {
        switch n {
        case ..<5: return 0
        case 5: return 30
        case 6: return 60
        case 7: return 300
        case 8: return 900
        default: return 3600
        }
    }

    func verify(_ pin: String) -> Result {
        guard let v = verifier else { return .notSet }
        var st = state
        if let until = st.lockedUntil, until > now() { return .locked(until: until) }
        let candidate = SecretPIN.derive(pin, salt: v.salt, iterations: v.iterations)
        if pin.count == v.length, SecretPIN.constantTimeEqual(candidate, v.hash) {
            state = State()
            return .ok
        }
        st.failures += 1
        let lock = SecretPIN.lockDuration(afterFailures: st.failures)
        st.lockedUntil = lock > 0 ? now().addingTimeInterval(lock) : nil
        state = st
        if let until = st.lockedUntil { return .locked(until: until) }
        return .wrong(remainingBeforeLock: max(0, 4 - st.failures))
    }

    static func derive(_ pin: String, salt: Data, iterations: Int) -> Data {
        var out = Data(count: 32)
        let pw = Array(pin.utf8)
        let rc = out.withUnsafeMutableBytes { o in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                     o.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        precondition(rc == kCCSuccess)
        return out
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var r: UInt8 = 0
        for i in 0..<a.count { r |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return r == 0
    }
}
