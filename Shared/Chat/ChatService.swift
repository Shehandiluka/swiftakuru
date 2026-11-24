import Foundation
import CryptoKit

struct ChatAccount: Codable, Equatable {
    let id: String
    var displayName: String
    var discoverable: Bool
    var phone: String           // own E.164 number, kept only on this device
    var keyVersion: Int
}

/// Coordinates the account, encryption, local database and the mailbox server.
/// Used by the app (full chat UI) and by the keyboard (Secret Chat panel). Never blocks typing:
/// every network call is async and failures leave messages in the local outbox for retry.
@MainActor
final class ChatService: ObservableObject {
    static let shared = ChatService()

    @Published private(set) var account: ChatAccount?
    @Published private(set) var revision = 0          // bumps when local data changes (UI refresh)
    @Published var lastError: String?
    @Published private(set) var syncing = false

    let db: ChatDB
    private var api: ChatAPI { ChatAPI(token: SecureStore.string(SecureStore.Keys.session)) }
    private var pollTask: Task<Void, Never>?

    init(db: ChatDB = .shared) {
        self.db = db
        account = SecureStore.codable(ChatAccount.self, SecureStore.Keys.account)
    }

    var isSignedIn: Bool { account != nil && SecureStore.string(SecureStore.Keys.session) != nil }
    var defaultCallingCode: String { SharedStore.shared.defaults.string(forKey: "chatCallingCode") ?? "94" }

    // MARK: registration
    func requestCode(phone: String) async throws {
        try await ChatAPI().start(phone: phone)
    }

    func verify(phone: String, code: String, name: String, discoverable: Bool) async throws {
        let key = ChatIdentity.currentOrCreate()
        let r = try await ChatAPI().verify(phone: phone, code: code, name: name, kemPub: ChatIdentity.publicBase64(key), discoverable: discoverable)
        SecureStore.setString(r.token, for: SecureStore.Keys.session)
        let acc = ChatAccount(id: r.user.id, displayName: r.user.displayName, discoverable: r.user.discoverable, phone: phone, keyVersion: r.user.keyVersion)
        SecureStore.setCodable(acc, for: SecureStore.Keys.account)
        account = acc
        if !r.created { db.setValue("0", "cursor.msg"); db.setValue("0", "cursor.evt") }
        await refreshConversations()
        await sync()
    }

    func updateProfile(name: String? = nil, discoverable: Bool? = nil) async {
        do {
            let me = try await api.updateMe(name: name, discoverable: discoverable)
            guard var acc = account else { return }
            acc.displayName = me.displayName; acc.discoverable = me.discoverable
            SecureStore.setCodable(acc, for: SecureStore.Keys.account); account = acc
        } catch { report(error) }
    }

    /// New encryption identity (e.g. suspected compromise). Partners are notified by the server.
    func rotateIdentityKey() async {
        let old = ChatIdentity.current()
        let new = ChatIdentity.create()
        do {
            let me = try await api.rotateKey(ChatIdentity.publicBase64(new))
            if var acc = account { acc.keyVersion = me.keyVersion; SecureStore.setCodable(acc, for: SecureStore.Keys.account); account = acc }
        } catch {
            if let o = old { SecureStore.set(o.rawRepresentation, for: SecureStore.Keys.identity) }
            report(error)
        }
    }

    func signOut(deleteAccount: Bool = false) async {
        if deleteAccount { try? await api.deleteAccount() } else { try? await api.logout() }
        stopPolling()
        SecureStore.delete(SecureStore.Keys.session)
        SecureStore.delete(SecureStore.Keys.account)
        ChatIdentity.delete()
        SecretPIN.shared.remove()
        db.wipeAll()
        account = nil
        bump()
    }

    func revokeOtherSessions() async { do { try await api.revokeOthers() } catch { report(error) } }

    // MARK: discovery & conversations
    func lookup(phone: String) async throws -> ChatAPI.User? {
        let r = try await api.lookup(phone: phone)
        return r.found ? r.user : nil
    }

    func startConversation(with user: ChatAPI.User, phone: String?) async throws -> String {
        let cid = try await api.startConversation(userId: user.id)
        db.upsertConversation(id: cid, partnerId: user.id, partnerName: user.displayName, partnerKey: user.kemPub ?? "", keyVersion: user.keyVersion, secret: false)
        db.setHidden(false, conversationId: cid)
        if let p = phone { db.indexSecret(phone: p, conversationId: cid) }
        bump()
        return cid
    }

    func refreshConversations() async {
        guard isSignedIn else { return }
        do {
            let list = try await api.conversations()
            for c in list {
                db.upsertConversation(id: c.id, partnerId: c.partner.id, partnerName: c.partner.displayName, partnerKey: c.partner.kemPub ?? "",
                                      keyVersion: c.partner.keyVersion, secret: c.secret, partnerDeleted: c.partner.deleted == true)
            }
            for inv in try await api.invitations() {
                db.upsertInvitation(ChatInvitation(id: inv.id, conversationId: inv.conversationId, fromName: inv.fromName ?? "", incoming: inv.toUser == account?.id, expiresAt: inv.expiresAt))
            }
            bump()
        } catch { report(error) }
    }

    func deleteConversation(_ id: String) async {
        db.deleteConversationLocally(id)
        bump()
        try? await api.hideConversation(id)
    }

    func block(_ c: ChatConversation) async {
        do { try await api.block(userId: c.partnerId); db.deleteConversationLocally(c.id); bump() } catch { report(error) }
    }
    func reportUser(_ c: ChatConversation, reason: String) async {
        do { try await api.report(userId: c.partnerId, conversationId: c.id, reason: reason) } catch { report(error) }
    }

    // MARK: Secret Chat
    func inviteToSecret(_ conversationId: String) async throws {
        let inv = try await api.invite(conversationId: conversationId)
        db.upsertInvitation(ChatInvitation(id: inv.id, conversationId: conversationId, fromName: account?.displayName ?? "", incoming: false, expiresAt: inv.expiresAt))
        bump()
    }
    func respond(_ inv: ChatInvitation, accept: Bool) async throws {
        try await api.respond(invitationId: inv.id, accept: accept)
        db.removeInvitation(inv.id)
        if accept { db.setSecret(true, conversationId: inv.conversationId) }
        bump()
    }
    func leaveSecret(_ conversationId: String) async {
        do { try await api.leaveSecret(conversationId: conversationId); db.setSecret(false, conversationId: conversationId); bump() } catch { report(error) }
    }

    /// Keyboard unlock: PIN already verified locally. Finds the Secret Chat for this phone number —
    /// first in the local index (works offline), then by asking the server (only own secret partners match).
    func secretConversation(forPhone phone: String) async -> ChatConversation? {
        if let cid = db.secretConversation(phone: phone), let c = db.conversation(cid), c.secret { return c }
        guard isSignedIn, let r = try? await api.resolveSecret(phone: phone), r.found, let cid = r.conversationId, let u = r.user else { return nil }
        db.upsertConversation(id: cid, partnerId: u.id, partnerName: u.displayName, partnerKey: u.kemPub ?? "", keyVersion: u.keyVersion, secret: true)
        db.indexSecret(phone: phone, conversationId: cid)
        return db.conversation(cid)
    }

    // MARK: messaging
    @discardableResult
    func send(_ text: String, in conversationId: String) async -> ChatMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4000 else { return nil }
        let m = ChatMessage(id: UUID().uuidString.lowercased(), conversationId: conversationId, outgoing: true, text: trimmed,
                            sentAt: Int(Date().timeIntervalSince1970), status: .pending, readByMe: true, serverSeq: 0)
        db.insertMessage(m)
        bump()
        await deliver(m)
        return m
    }

    private func deliver(_ m: ChatMessage, retriedKey: Bool = false) async {
        guard let me = account, let myKey = ChatIdentity.current(), let conv = db.conversation(m.conversationId) else { return }
        do {
            let pub = try ChatCrypto.publicKey(fromBase64: conv.partnerKey)
            let aad = ChatCrypto.aad(messageId: m.id, conversationId: conv.id, senderId: me.id, recipientId: conv.partnerId, sentAt: m.sentAt, recipientKeyVersion: conv.partnerKeyVersion)
            let sealed = try ChatCrypto.seal(.init(text: m.text, sentAt: m.sentAt), to: pub, from: myKey, aad: aad)
            let r = try await api.send(id: m.id, conversationId: conv.id, enc: sealed.enc.base64EncodedString(), ciphertext: sealed.ciphertext.base64EncodedString(),
                                       keyVersion: conv.partnerKeyVersion, sentAt: m.sentAt)
            db.setServerSeq(r.seq, id: m.id)
        } catch let e as ChatAPI.APIError where e.code == "stale_key" && !retriedKey {
            await refreshConversations()                 // picks up the partner's new key → safety warning in UI
            await deliver(m, retriedKey: true)
            return
        } catch let e as ChatAPI.APIError where e.status >= 400 && e.status < 500 && e.status != 429 {
            db.bumpAttempts(id: m.id, failed: true)
            lastError = e.code
        } catch {
            db.bumpAttempts(id: m.id, failed: false)     // offline / server error → stays pending, retried on next sync
        }
        bump()
    }

    func retryOutbox() async {
        for m in db.outbox() { await deliver(m) }
    }

    /// Pulls new messages and events, decrypts, stores, acknowledges. Safe to call often.
    func sync() async {
        guard isSignedIn, !syncing, let myKey = ChatIdentity.current() else { return }
        syncing = true
        defer { syncing = false }
        await retryOutbox()
        do {
            let afterM = Int(db.value("cursor.msg") ?? "0") ?? 0
            let afterE = Int(db.value("cursor.evt") ?? "0") ?? 0
            let r = try await api.sync(after: afterM, events: afterE)
            var delivered: [String] = []
            var needsRefresh = false
            for msg in r.messages {
                if db.hasMessage(msg.id) { delivered.append(msg.id); continue }          // duplicate / replay → drop
                if db.conversation(msg.conversationId) == nil { await refreshConversations() }
                guard let conv = db.conversation(msg.conversationId), conv.partnerId == msg.senderId,
                      let senderKey = try? ChatCrypto.publicKey(fromBase64: conv.partnerKey),
                      let enc = Data(base64Encoded: msg.enc), let ct = Data(base64Encoded: msg.ciphertext) else {
                    needsRefresh = true; continue
                }
                let aad = ChatCrypto.aad(messageId: msg.id, conversationId: msg.conversationId, senderId: msg.senderId, recipientId: account?.id ?? "",
                                         sentAt: msg.sentAt, recipientKeyVersion: msg.keyVersion)
                let text: String
                if let env = try? ChatCrypto.open(.init(enc: enc, ciphertext: ct), with: myKey, from: senderKey, aad: aad), env.sentAt == msg.sentAt {
                    text = env.text
                } else {
                    text = "🔒 මේ පණිවිඩය decrypt කරන්න බැරි වුණා (key එක වෙනස් වෙලා වෙන්න පුළුවන්)"
                }
                db.insertMessage(ChatMessage(id: msg.id, conversationId: msg.conversationId, outgoing: false, text: text, sentAt: msg.sentAt,
                                             status: .received, readByMe: false, serverSeq: msg.seq))
                delivered.append(msg.id)
            }
            if let last = r.messages.last { db.setValue(String(last.seq), "cursor.msg") }
            if !delivered.isEmpty { try? await api.ack(delivered: delivered, read: []) }
            for e in r.events { apply(e) }
            if let last = r.events.last { db.setValue(String(last.seq), "cursor.evt"); try? await api.ackEvents(upTo: last.seq) }
            if needsRefresh { await refreshConversations() }
            bump()
        } catch { report(error) }
    }

    private func apply(_ e: ChatAPI.Event) {
        let p = e.payload
        switch e.type {
        case "status":
            db.setStatus(.delivered, ids: p["delivered"]?.strings ?? [])
            db.setStatus(.read, ids: p["read"]?.strings ?? [])
        case "invite":
            if let id = p["id"]?.string, let cid = p["conversationId"]?.string {
                db.upsertInvitation(ChatInvitation(id: id, conversationId: cid, fromName: p["fromName"]?.string ?? "", incoming: true, expiresAt: p["expiresAt"]?.int ?? 0))
            }
        case "invite_response":
            if let id = p["invitationId"]?.string { db.removeInvitation(id) }
        case "secret":
            if let cid = p["conversationId"]?.string {
                let on = p["secret"]?.bool ?? false
                db.setSecret(on, conversationId: cid)
                db.removeInvitations(conversationId: cid)
            }
        case "key_changed":
            if let uid = p["userId"]?.string, let k = p["kemPub"]?.string, let v = p["keyVersion"]?.int { db.updatePartnerKey(userId: uid, key: k, version: v) }
        case "conversation":
            if let cid = p["conversationId"]?.string, p["partnerDeleted"]?.bool == true { db.markPartnerDeleted(conversationId: cid) }
        default: break
        }
    }

    func markRead(_ conversationId: String) async {
        let ids = db.unreadIncoming(conversationId: conversationId)
        guard !ids.isEmpty else { return }
        db.markReadByMe(ids: ids)
        bump()
        try? await api.ack(delivered: [], read: ids)
    }

    // MARK: polling (no push notifications without a paid Apple developer account)
    func startPolling(every seconds: Double = 3) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }
    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    func clearLocalCache() { db.clearMessages(); bump() }

    func trustNewKey(_ conversationId: String) { db.trustCurrentKey(conversationId: conversationId); bump() }

    private func bump() { revision &+= 1 }
    private func report(_ e: Error) {
        if let a = e as? ChatAPI.APIError { lastError = a.code } else { lastError = (e as NSError).localizedDescription }
    }
}
