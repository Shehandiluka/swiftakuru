import XCTest
import CryptoKit

// Unit tests for the Secret Chat building blocks. They run on the iOS Simulator in GitHub Actions
// (see .github/workflows/build.yml) — no network, no Keychain. The Shared/ sources are compiled into the test bundle.

final class PhoneNumberTests: XCTestCase {
    func testSriLankanFormats() {
        XCTAssertEqual(PhoneNumber.normalize("0771234567"), "+94771234567")
        XCTAssertEqual(PhoneNumber.normalize("077 123 4567"), "+94771234567")
        XCTAssertEqual(PhoneNumber.normalize("771234567"), "+94771234567")
        XCTAssertEqual(PhoneNumber.normalize("+94 77 123-4567"), "+94771234567")
        XCTAssertEqual(PhoneNumber.normalize("0094771234567"), "+94771234567")
        XCTAssertEqual(PhoneNumber.normalize("94771234567"), "+94771234567")
    }
    func testOtherCountries() {
        XCTAssertEqual(PhoneNumber.normalize("0501234567", defaultCallingCode: "972"), "+972501234567")
        XCTAssertEqual(PhoneNumber.normalize("+1 (415) 555-0100"), "+14155550100")
    }
    func testRejectsGarbage() {
        XCTAssertNil(PhoneNumber.normalize(""))
        XCTAssertNil(PhoneNumber.normalize("12"))
        XCTAssertNil(PhoneNumber.normalize("+0771234567"))
        XCTAssertNil(PhoneNumber.normalize("07712abc67"))
        XCTAssertNil(PhoneNumber.normalize("+94+771234567"))
        XCTAssertNil(PhoneNumber.normalize("+12345678901234567"))
        XCTAssertTrue(PhoneNumber.isValidE164("+94771234567"))
        XCTAssertFalse(PhoneNumber.isValidE164("0771234567"))
    }
}

final class SecretCommandTests: XCTestCase {
    func testOriginalConcept() {
        // "PIN 1357 + 0771234567" typed as one command
        XCTAssertEqual(SecretCommand.parse("13570771234567", pinLength: 4, defaultCallingCode: "94"),
                       .init(pin: "1357", phone: "+94771234567"))
    }
    func testInternationalAndSixDigitPin() {
        XCTAssertEqual(SecretCommand.parse("246810+972501234567", pinLength: 6, defaultCallingCode: "94"),
                       .init(pin: "246810", phone: "+972501234567"))
    }
    func testInvalidCommands() {
        XCTAssertNil(SecretCommand.parse("1357", pinLength: 4, defaultCallingCode: "94"))           // no phone
        XCTAssertNil(SecretCommand.parse("13570", pinLength: 4, defaultCallingCode: "94"))          // phone too short
        XCTAssertNil(SecretCommand.parse("13a70771234567", pinLength: 4, defaultCallingCode: "94")) // non-digit PIN
        XCTAssertNil(SecretCommand.parse("13570771234567", pinLength: 3, defaultCallingCode: "94")) // bad PIN length
    }
}

final class SecretPINTests: XCTestCase {
    func make() -> SecretPIN { SecretPIN(storage: MemoryPINStorage(), iterations: 1000) }

    func testSetAndVerify() {
        let p = make()
        XCTAssertEqual(p.verify("2468"), .notSet)
        XCTAssertTrue(p.set("2468"))
        XCTAssertEqual(p.length, 4)
        XCTAssertEqual(p.verify("2468"), .ok)
        if case .wrong = p.verify("2469") {} else { XCTFail("wrong PIN accepted") }
    }
    func testWeakPinsRejected() {
        let p = make()
        for weak in ["1234", "0000", "1111", "123", "123456789", "12a4"] { XCTAssertFalse(p.set(weak), weak) }
    }
    func testStoredAsHashNotPlaintext() {
        let s = MemoryPINStorage()
        let p = SecretPIN(storage: s, iterations: 1000)
        XCTAssertTrue(p.set("97531"))
        let stored = s.items[SecureStore.Keys.pin]!
        XCTAssertNil(String(data: stored, encoding: .utf8)?.range(of: "97531"), "PIN must not be stored in plaintext")
        XCTAssertNil(stored.range(of: Data("97531".utf8)))
        // two devices / two set() calls with the same PIN → different salt → different hash
        let s2 = MemoryPINStorage(); _ = SecretPIN(storage: s2, iterations: 1000).set("97531")
        XCTAssertNotEqual(stored, s2.items[SecureStore.Keys.pin])
    }
    func testChangeRequiresCurrent() {
        let p = make()
        XCTAssertTrue(p.set("2468"))
        XCTAssertFalse(p.set("1357", current: "0000"))
        XCTAssertTrue(p.set("1357", current: "2468"))
        XCTAssertEqual(p.verify("1357"), .ok)
    }
    func testBruteForceLockout() {
        let p = make()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        p.now = { clock }
        XCTAssertTrue(p.set("2468"))
        for i in 1...4 { XCTAssertEqual(p.verify("0001"), .wrong(remainingBeforeLock: 4 - i)) }
        guard case .locked(let until) = p.verify("0002") else { return XCTFail("5th failure must lock") }
        XCTAssertEqual(until.timeIntervalSince(clock), 30, accuracy: 0.5)
        // even the right PIN is refused while locked
        if case .locked = p.verify("2468") {} else { XCTFail("correct PIN accepted during lockout") }
        clock = clock.addingTimeInterval(31)
        guard case .locked(let until2) = p.verify("0003") else { return XCTFail("6th failure must lock longer") }
        XCTAssertEqual(until2.timeIntervalSince(clock), 60, accuracy: 0.5)
        clock = clock.addingTimeInterval(61)
        XCTAssertEqual(p.verify("2468"), .ok)
        XCTAssertEqual(p.state.failures, 0, "success resets the counter")
    }
    func testLockSchedule() {
        XCTAssertEqual(SecretPIN.lockDuration(afterFailures: 4), 0)
        XCTAssertEqual(SecretPIN.lockDuration(afterFailures: 5), 30)
        XCTAssertEqual(SecretPIN.lockDuration(afterFailures: 8), 900)
        XCTAssertEqual(SecretPIN.lockDuration(afterFailures: 50), 3600)
    }
}

@available(iOS 17.0, *)
final class ChatCryptoTests: XCTestCase {
    let alice = Curve25519.KeyAgreement.PrivateKey()
    let bob = Curve25519.KeyAgreement.PrivateKey()
    let mallory = Curve25519.KeyAgreement.PrivateKey()
    func aad(_ id: String = "m1", conv: String = "c1") -> Data {
        ChatCrypto.aad(messageId: id, conversationId: conv, senderId: "A", recipientId: "B", sentAt: 100, recipientKeyVersion: 1)
    }

    func testRoundTrip() throws {
        let sealed = try ChatCrypto.seal(.init(text: "ආයුබෝවන් 👋", sentAt: 100), to: bob.publicKey, from: alice, aad: aad())
        XCTAssertNil(sealed.ciphertext.range(of: Data("ආයුබෝවන්".utf8)), "ciphertext must not contain plaintext")
        let env = try ChatCrypto.open(sealed, with: bob, from: alice.publicKey, aad: aad())
        XCTAssertEqual(env.text, "ආයුබෝවන් 👋")
    }
    func testEachMessageUsesFreshEphemeralKey() throws {
        let a = try ChatCrypto.seal(.init(text: "hi", sentAt: 100), to: bob.publicKey, from: alice, aad: aad())
        let b = try ChatCrypto.seal(.init(text: "hi", sentAt: 100), to: bob.publicKey, from: alice, aad: aad())
        XCTAssertNotEqual(a.enc, b.enc); XCTAssertNotEqual(a.ciphertext, b.ciphertext)
    }
    func testWrongRecipientKeyFails() throws {
        let sealed = try ChatCrypto.seal(.init(text: "secret", sentAt: 100), to: bob.publicKey, from: alice, aad: aad())
        XCTAssertThrowsError(try ChatCrypto.open(sealed, with: mallory, from: alice.publicKey, aad: aad()))
    }
    func testImpersonatedSenderFails() throws {
        // Mallory encrypts to Bob but claims to be Alice → auth mode rejects it.
        let sealed = try ChatCrypto.seal(.init(text: "I am Alice", sentAt: 100), to: bob.publicKey, from: mallory, aad: aad())
        XCTAssertThrowsError(try ChatCrypto.open(sealed, with: bob, from: alice.publicKey, aad: aad()))
    }
    func testTamperingDetected() throws {
        let sealed = try ChatCrypto.seal(.init(text: "pay 100", sentAt: 100), to: bob.publicKey, from: alice, aad: aad())
        var ct = sealed.ciphertext; ct[ct.startIndex] ^= 0x01
        XCTAssertThrowsError(try ChatCrypto.open(.init(enc: sealed.enc, ciphertext: ct), with: bob, from: alice.publicKey, aad: aad()))
    }
    func testReplayIntoOtherConversationOrIdFails() throws {
        let sealed = try ChatCrypto.seal(.init(text: "hello", sentAt: 100), to: bob.publicKey, from: alice, aad: aad("m1", conv: "c1"))
        XCTAssertThrowsError(try ChatCrypto.open(sealed, with: bob, from: alice.publicKey, aad: aad("m2", conv: "c1")))
        XCTAssertThrowsError(try ChatCrypto.open(sealed, with: bob, from: alice.publicKey, aad: aad("m1", conv: "c2")))
    }
    func testInvalidKeyRejected() {
        XCTAssertThrowsError(try ChatCrypto.publicKey(fromBase64: "not-base64"))
        XCTAssertThrowsError(try ChatCrypto.publicKey(fromBase64: Data(count: 16).base64EncodedString()))
    }
    func testSafetyNumberIsSymmetric() {
        let a = alice.publicKey.rawRepresentation.base64EncodedString(), b = bob.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertEqual(ChatCrypto.safetyNumber(a, b), ChatCrypto.safetyNumber(b, a))
        XCTAssertNotEqual(ChatCrypto.safetyNumber(a, b), ChatCrypto.safetyNumber(a, mallory.publicKey.rawRepresentation.base64EncodedString()))
    }
}

final class ChatDBTests: XCTestCase {
    var db: ChatDB!
    var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).sqlite")
        db = ChatDB(url: url, key: SymmetricKey(size: .bits256))
        db.upsertConversation(id: "c1", partnerId: "B", partnerName: "Bee", partnerKey: "K1", keyVersion: 1, secret: false)
    }
    override func tearDown() { db = nil; try? FileManager.default.removeItem(at: url) }

    func msg(_ id: String, _ t: Int, out: Bool = false, text: String = "x") -> ChatMessage {
        ChatMessage(id: id, conversationId: "c1", outgoing: out, text: text, sentAt: t, status: out ? .pending : .received, readByMe: out, serverSeq: t)
    }

    func testDuplicateMessagesIgnored() {
        XCTAssertTrue(db.insertMessage(msg("m1", 1)))
        XCTAssertFalse(db.insertMessage(msg("m1", 1)), "same id twice must be dropped (retry / replay)")
        XCTAssertEqual(db.messages(conversationId: "c1").count, 1)
    }
    func testOrderingAndLatestFive() {
        for i in [5, 1, 7, 3, 2, 6, 4] { db.insertMessage(msg("m\(i)", i)) }
        XCTAssertEqual(db.messages(conversationId: "c1").map(\.sentAt), [1, 2, 3, 4, 5, 6, 7])
        let five = LatestMessages.latest(db.messages(conversationId: "c1"))
        XCTAssertEqual(five.map(\.sentAt), [3, 4, 5, 6, 7])
        // a new message pushes the oldest visible one out; nothing is deleted from storage
        db.insertMessage(msg("m8", 8))
        XCTAssertEqual(LatestMessages.latest(db.messages(conversationId: "c1")).map(\.sentAt), [4, 5, 6, 7, 8])
        XCTAssertEqual(db.messages(conversationId: "c1").count, 8)
    }
    func testBodiesEncryptedAtRest() throws {
        db.insertMessage(msg("m1", 1, text: "රහස් පණිවිඩය"))
        db = nil
        let raw = try Data(contentsOf: url) + ((try? Data(contentsOf: URL(fileURLWithPath: url.path + "-wal"))) ?? Data())
        XCTAssertNil(raw.range(of: Data("රහස් පණිවිඩය".utf8)), "plaintext must not be in the database file")
    }
    func testOutboxRetryAndStatusNeverGoesBackwards() {
        db.insertMessage(msg("o1", 1, out: true))
        XCTAssertEqual(db.outbox().map(\.id), ["o1"])
        db.bumpAttempts(id: "o1", failed: false)          // offline → still pending
        XCTAssertEqual(db.outbox().map(\.id), ["o1"])
        db.setServerSeq(10, id: "o1")                       // delivered to server
        XCTAssertTrue(db.outbox().isEmpty)
        db.setStatus(.read, ids: ["o1"])
        db.setStatus(.delivered, ids: ["o1"])               // late "delivered" must not override "read"
        XCTAssertEqual(db.messages(conversationId: "c1").first?.status, .read)
    }
    func testUnreadCount() {
        db.insertMessage(msg("i1", 1)); db.insertMessage(msg("i2", 2)); db.insertMessage(msg("o1", 3, out: true))
        XCTAssertEqual(db.unreadCount(conversationId: "c1"), 2)
        db.markReadByMe(ids: db.unreadIncoming(conversationId: "c1"))
        XCTAssertEqual(db.unreadCount(conversationId: "c1"), 0)
    }
    func testKeyChangeDetection() {
        XCTAssertFalse(db.conversation("c1")!.keyChanged)
        db.updatePartnerKey(userId: "B", key: "K2", version: 2)
        XCTAssertTrue(db.conversation("c1")!.keyChanged, "a new partner key must raise a warning")
        db.trustCurrentKey(conversationId: "c1")
        XCTAssertFalse(db.conversation("c1")!.keyChanged)
    }
    func testSecretIndexByPhone() {
        db.indexSecret(phone: "+94771234567", conversationId: "c1")
        XCTAssertEqual(db.secretConversation(phone: "+94771234567"), "c1")
        XCTAssertNil(db.secretConversation(phone: "+94771234568"))
        let raw = (try? Data(contentsOf: url)) ?? Data()
        XCTAssertNil(raw.range(of: Data("771234567".utf8)), "phone numbers are stored only as keyed hashes")
    }
}

// MARK: - v1.3 features
final class EnvelopeAndMediaTests: XCTestCase {
    func testV1EnvelopeStillDecodes() throws {
        let v1 = Data(#"{"text":"hello","sentAt":5}"#.utf8)
        let e = try JSONDecoder().decode(ChatCrypto.Envelope.self, from: v1)
        XCTAssertEqual(e.text, "hello"); XCTAssertNil(e.kind); XCTAssertNil(e.media)
    }
    func testMediaEncryptRoundTripAndTamper() throws {
        let data = Data((0..<5000).map { UInt8($0 % 251) })
        let (box, key) = try MediaCipher.encrypt(data)
        XCTAssertNil(box.range(of: data.prefix(64)), "ciphertext must not contain the file bytes")
        XCTAssertEqual(try MediaCipher.decrypt(box, key: key), data)
        var bad = box; bad[bad.startIndex + 20] ^= 0xFF
        XCTAssertThrowsError(try MediaCipher.decrypt(bad, key: key), "tampered attachment must fail")
        let (_, otherKey) = try MediaCipher.encrypt(Data([1]))
        XCTAssertThrowsError(try MediaCipher.decrypt(box, key: otherKey), "wrong key must fail")
    }
}

final class ChatDBv2Tests: XCTestCase {
    var db: ChatDB!
    var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("chat2-\(UUID().uuidString).sqlite")
        db = ChatDB(url: url, key: SymmetricKey(size: .bits256))
        db.upsertConversation(id: "c1", partnerId: "B", partnerName: "Bee", partnerKey: "K1", keyVersion: 1, secret: true)
    }
    override func tearDown() { db = nil; try? FileManager.default.removeItem(at: url) }
    func msg(_ id: String, _ t: Int, out: Bool = false, ttl: Int? = nil, kind: String = "text") -> ChatMessage {
        var m = ChatMessage(id: id, conversationId: "c1", outgoing: out, text: "t\(t)", sentAt: t, status: out ? .sent : .received, readByMe: out, serverSeq: t, kind: kind)
        m.ttl = ttl
        return m
    }

    func testDisappearingCountdownStartsWhenRead() {
        db.insertMessage(msg("d1", 1, ttl: 30))
        XCTAssertNil(db.message("d1")?.expiresAt, "not counting before it is read")
        XCTAssertEqual(db.deleteExpired(now: 10_000_000_000), 0, "unread disappearing message is kept")
        db.markReadByMe(ids: ["d1"], now: 1000)
        XCTAssertEqual(db.message("d1")?.expiresAt, 1030)
        XCTAssertEqual(db.deleteExpired(now: 1029), 0)
        XCTAssertEqual(db.deleteExpired(now: 1031), 1)
        XCTAssertNil(db.message("d1"), "expired message removed from the device")
    }
    func testKeepLastFive() {
        for i in 1...8 { db.insertMessage(msg("k\(i)", i)) }
        db.setKeepLast(5, conversationId: "c1")
        XCTAssertEqual(db.messages(conversationId: "c1").map(\.sentAt), [4, 5, 6, 7, 8])
        db.insertMessage(msg("k9", 9))
        XCTAssertEqual(db.messages(conversationId: "c1").map(\.sentAt), [5, 6, 7, 8, 9], "older messages are actually deleted")
        XCTAssertNil(db.message("k4"))
    }
    func testDeleteForEveryoneWipesContent() throws {
        var m = msg("x1", 1, out: true)
        m.text = "මකන්න ඕන රහස"
        m.media = ChatCrypto.MediaRef(id: "m1", key: "k", mime: "image/jpeg", name: "a.jpg", size: 10)
        db.insertMessage(m)
        db.markDeleted(id: "x1")
        let after = try XCTUnwrap(db.message("x1"))
        XCTAssertTrue(after.deleted); XCTAssertEqual(after.text, ""); XCTAssertNil(after.media)
    }
    func testControlMessagesHiddenAndReplyStored() {
        db.insertMessage(msg("c1m", 1, out: true, kind: "ctl"))
        var r = msg("r1", 2)
        r.replyTo = "x"; r.replyText = "quoted"
        db.insertMessage(r)
        let visible = db.messages(conversationId: "c1")
        XCTAssertEqual(visible.map(\.id), ["r1"], "control messages never show")
        XCTAssertEqual(visible.first?.replyText, "quoted")
        XCTAssertEqual(db.outbox().map(\.id), [], "sent control messages are not pending")
    }
    func testMessageRequestDetection() {
        db.upsertConversation(id: "c2", partnerId: "C", partnerName: "Cee", partnerKey: "K", keyVersion: 1, secret: false, accepted: false, requestedBy: "C")
        db.upsertConversation(id: "c3", partnerId: "D", partnerName: "Dee", partnerKey: "K", keyVersion: 1, secret: false, accepted: false, requestedBy: "ME")
        XCTAssertTrue(db.conversation("c2")!.isIncomingRequest(myId: "ME"))
        XCTAssertFalse(db.conversation("c3")!.isIncomingRequest(myId: "ME"), "my own request is not an incoming request")
        db.setAccepted(conversationId: "c2")
        XCTAssertFalse(db.conversation("c2")!.isIncomingRequest(myId: "ME"))
    }
}
