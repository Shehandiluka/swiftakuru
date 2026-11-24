import Foundation
import Security

/// Keychain storage shared by the app and the keyboard. The App Group (when the install has one)
/// doubles as the keychain access group, so the keyboard can read the session and keys the app created.
/// Items are "this device only" — they are not in backups and don't move to another phone.
enum SecureStore {
    static let service = "store.swiftpaypos.swiftakuru.chat"

    private static func base(_ key: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        if let g = SharedStore.shared.activeGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    @discardableResult
    static func set(_ data: Data, for key: String) -> Bool {
        var q = base(key)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let st = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if st == errSecSuccess { return true }
        if st == errSecItemNotFound {
            for (k, v) in attrs { q[k] = v }
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func get(_ key: String) -> Data? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ key: String) { SecItemDelete(base(key) as CFDictionary) }

    static func setString(_ s: String, for key: String) { set(Data(s.utf8), for: key) }
    static func string(_ key: String) -> String? { get(key).flatMap { String(data: $0, encoding: .utf8) } }

    static func setCodable<T: Encodable>(_ v: T, for key: String) { if let d = try? JSONEncoder().encode(v) { set(d, for: key) } }
    static func codable<T: Decodable>(_ t: T.Type, _ key: String) -> T? { get(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }

    enum Keys {
        static let session = "session"          // bearer token
        static let account = "account"          // ChatAccount JSON (id, name, phone)
        static let identity = "identity.x25519" // private key raw representation
        static let pin = "pin"                  // PIN verifier (PBKDF2 hash + salt)
        static let pinState = "pin.state"       // failed attempts / lockout
        static let dbKey = "db.key"             // AES key for message bodies in the local database
    }
}
