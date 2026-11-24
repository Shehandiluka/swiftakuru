import Foundation
import CryptoKit

/// End-to-end encryption for Swift Akuru Chat.
///
/// Construction: HPKE (RFC 9180) in **Auth mode** with DHKEM(X25519, HKDF-SHA256), HKDF-SHA256 and
/// ChaCha20-Poly1305, as implemented by Apple CryptoKit (iOS 17+). Every message uses a fresh HPKE
/// sender context (new ephemeral key). Auth mode binds the sender's long-term X25519 key, so the recipient
/// knows which identity sent it. The additional authenticated data binds the message to its id,
/// conversation, sender, recipient, time and the recipient key version, so a ciphertext can't be replayed
/// into another conversation or under another id; repeated ids are dropped by the local database.
///
/// Limits (honest): no Double Ratchet → no post-compromise security, and forward secrecy only on the
/// sender side (ephemeral key per message); if a recipient's long-term private key is stolen, past
/// ciphertexts captured in transit could be decrypted. Identity keys never leave the device's Keychain.
enum ChatCrypto {
    static let info = Data("SwiftAkuru-Chat-v1".utf8)

    struct Sealed: Equatable { let enc: Data; let ciphertext: Data }

    struct Envelope: Codable, Equatable {
        let text: String
        let sentAt: Int
    }

    enum CryptoError: Error { case unsupportedOS, badKey, decryptFailed }

    static var isSupported: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }

    static func aad(messageId: String, conversationId: String, senderId: String, recipientId: String, sentAt: Int, recipientKeyVersion: Int) -> Data {
        Data("v1|\(messageId)|\(conversationId)|\(senderId)|\(recipientId)|\(sentAt)|\(recipientKeyVersion)".utf8)
    }

    static func publicKey(fromBase64 b64: String) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let d = Data(base64Encoded: b64), d.count == 32 else { throw CryptoError.badKey }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: d)
    }

    static func seal(_ envelope: Envelope, to recipient: Curve25519.KeyAgreement.PublicKey,
                     from sender: Curve25519.KeyAgreement.PrivateKey, aad: Data) throws -> Sealed {
        guard #available(iOS 17.0, *) else { throw CryptoError.unsupportedOS }
        let plaintext = try JSONEncoder().encode(envelope)
        var ctx = try HPKE.Sender(recipientKey: recipient, ciphersuite: .Curve25519_SHA256_ChachaPoly, info: info, authenticatedBy: sender)
        let ct = try ctx.seal(plaintext, authenticating: aad)
        return Sealed(enc: ctx.encapsulatedKey, ciphertext: ct)
    }

    static func open(_ sealed: Sealed, with recipient: Curve25519.KeyAgreement.PrivateKey,
                     from sender: Curve25519.KeyAgreement.PublicKey, aad: Data) throws -> Envelope {
        guard #available(iOS 17.0, *) else { throw CryptoError.unsupportedOS }
        do {
            var ctx = try HPKE.Recipient(privateKey: recipient, ciphersuite: .Curve25519_SHA256_ChachaPoly, info: info,
                                         encapsulatedKey: sealed.enc, authenticatedBy: sender)
            let pt = try ctx.open(sealed.ciphertext, authenticating: aad)
            return try JSONDecoder().decode(Envelope.self, from: pt)
        } catch {
            throw CryptoError.decryptFailed
        }
    }

    /// Safety number both people can compare (e.g. read it out on a call) to detect a swapped key.
    static func safetyNumber(_ a: String, _ b: String) -> String {
        let keys = [a, b].sorted().joined(separator: "|")
        let digest = SHA256.hash(data: Data(keys.utf8))
        let bytes = Array(digest)
        var groups: [String] = []
        for i in 0..<6 {
            let v = (UInt32(bytes[i * 3]) << 16 | UInt32(bytes[i * 3 + 1]) << 8 | UInt32(bytes[i * 3 + 2])) % 100_000
            groups.append(String(format: "%05d", v))
        }
        return groups.joined(separator: " ")
    }
}

/// This device's long-term X25519 identity, kept in the Keychain (this device only).
enum ChatIdentity {
    static func current() -> Curve25519.KeyAgreement.PrivateKey? {
        guard let d = SecureStore.get(SecureStore.Keys.identity) else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: d)
    }
    @discardableResult
    static func create() -> Curve25519.KeyAgreement.PrivateKey {
        let k = Curve25519.KeyAgreement.PrivateKey()
        SecureStore.set(k.rawRepresentation, for: SecureStore.Keys.identity)
        return k
    }
    static func currentOrCreate() -> Curve25519.KeyAgreement.PrivateKey { current() ?? create() }
    static func publicBase64(_ k: Curve25519.KeyAgreement.PrivateKey) -> String { k.publicKey.rawRepresentation.base64EncodedString() }
    static func delete() { SecureStore.delete(SecureStore.Keys.identity) }
}

/// AES-GCM encryption for message bodies stored in the local SQLite database.
enum LocalCipher {
    static func key() -> SymmetricKey {
        if let d = SecureStore.get(SecureStore.Keys.dbKey), d.count == 32 { return SymmetricKey(data: d) }
        let k = SymmetricKey(size: .bits256)
        SecureStore.set(k.withUnsafeBytes { Data($0) }, for: SecureStore.Keys.dbKey)
        return k
    }
    static func seal(_ s: String, key: SymmetricKey) -> Data? { try? AES.GCM.seal(Data(s.utf8), using: key).combined }
    static func open(_ d: Data, key: SymmetricKey) -> String? {
        guard let box = try? AES.GCM.SealedBox(combined: d), let pt = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: pt, encoding: .utf8)
    }
    /// Keyed hash of a phone number for the offline keyboard index (never the number itself).
    static func phoneTag(_ e164: String, key: SymmetricKey) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Data(("phone:" + e164).utf8), using: key)).base64EncodedString()
    }
}
