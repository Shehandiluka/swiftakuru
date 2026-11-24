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
    @Published private(set) var me: ChatAPI.Me?
    @Published private(set) var revision = 0          // bumps when local data changes (UI refresh)
    @Published var lastError: String?
    @Published private(set) var syncing = false
    @Published private(set) var typingUntil: [String: Date] = [:]

    let db: ChatDB
    private var api: ChatAPI { ChatAPI(token: SecureStore.string(SecureStore.Keys.session)) }
    private var pollTask: Task<Void, Never>?
    private var lastTypingSent: [String: Date] = [:]

    static let ttlChoices: [(Int, String)] = [(0, "Off"), (30, "30s"), (60, "1 min"), (300, "5 min"), (3600, "1 hour"), (86400, "24 hours")]
    static func ttlLabel(_ s: Int) -> String {
        if let c = ttlChoices.first(where: { $0.0 == s }) { return c.1 }
        if s % 3600 == 0 { return "\(s / 3600) h" }
        if s % 60 == 0 { return "\(s / 60) min" }
        return "\(s)s"
    }

    init(db: ChatDB = .shared) {
        self.db = db
        account = SecureStore.codable(ChatAccount.self, SecureStore.Keys.account)
    }

    var isSignedIn: Bool { account != nil && SecureStore.string(SecureStore.Keys.session) != nil }
    var defaultCallingCode: String { SharedStore.shared.defaults.string(forKey: "chatCallingCode") ?? "94" }
    func isTyping(_ cid: String) -> Bool { (typingUntil[cid] ?? .distantPast) > Date() }

    // MARK: registration & profile
    func requestCode(phone: String) async throws { try await ChatAPI().start(phone: phone) }

    func verify(phone: String, code: String, name: String, discoverable: Bool) async throws {
        let key = ChatIdentity.currentOrCreate()
        let r = try await ChatAPI().verify(phone: phone, code: code, name: name, kemPub: ChatIdentity.publicBase64(key), discoverable: discoverable)
        SecureStore.setString(r.token, for: SecureStore.Keys.session)
        let acc = ChatAccount(id: r.user.id, displayName: r.user.displayName, discoverable: r.user.discoverable, phone: phone, keyVersion: r.user.keyVersion)
        SecureStore.setCodable(acc, for: SecureStore.Keys.account)
        account = acc
        me = r.user
        if !r.created { db.setValue("0", "cursor.msg"); db.setValue("0", "cursor.evt") }
        await refreshConversations()
        await sync()
    }

    func loadProfile() async {
        guard isSignedIn else { return }
        do { apply(try await api.me()) } catch { report(error) }
    }

    private func apply(_ m: ChatAPI.Me) {
        me = m
        guard var acc = account else { return }
        acc.displayName = m.displayName; acc.discoverable = m.discoverable; acc.keyVersion = m.keyVersion
        SecureStore.setCodable(acc, for: SecureStore.Keys.account); account = acc
    }

    /// Profile & privacy: displayName, discoverable, allowRequests, readReceipts, profileVisibility, lastSeenVisibility.
    func updateSettings(_ fields: [String: Any]) async {
        do { apply(try await api.updateMe(fields)) } catch { report(error) }
    }
    func updateProfile(name: String? = nil, discoverable: Bool? = nil) async {
        var f: [String: Any] = [:]
        if let n = name { f["displayName"] = n }
        if let d = discoverable { f["discoverable"] = d }
        await updateSettings(f)
    }

    /// JPEG data (already resized by the UI to ≤ 256 px). nil removes the picture.
    func setAvatar(_ jpeg: Data?) async {
        do { apply(try await api.setAvatar(jpeg?.base64EncodedString())) } catch { report(error) }
    }

    /// New encryption identity (e.g. suspected compromise). Partners are notified by the server.
    func rotateIdentityKey() async {
        let old = ChatIdentity.current()
        let new = ChatIdentity.create()
        do { apply(try await api.rotateKey(ChatIdentity.publicBase64(new))) } catch {
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
        account = nil; me = nil
        bump()
    }

    func revokeOtherSessions() async { do { try await api.revokeOthers() } catch { report(error) } }
    func blockedUsers() async -> [ChatAPI.Blocked] { (try? await api.blocked()) ?? [] }
    func unblock(_ userId: String) async { do { try await api.unblock(userId: userId) } catch { report(error) } }

    // MARK: discovery & conversations
    func lookup(phone: String) async throws -> ChatAPI.User? {
        let r = try await api.lookup(phone: phone)
        return r.found ? r.user : nil
    }

    func startConversation(with user: ChatAPI.User, phone: String?) async throws -> String {
        let cid = try await api.startConversation(userId: user.id)
        let existing = db.conversation(cid)
        db.upsertConversation(id: cid, partnerId: user.id, partnerName: user.displayName, partnerKey: user.kemPub ?? "", keyVersion: user.keyVersion,
                              secret: existing?.secret ?? false, accepted: existing?.accepted ?? false, requestedBy: existing?.requestedBy ?? account?.id,
                              partnerAvatar: user.avatar)
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
                                      keyVersion: c.partner.keyVersion, secret: c.secret, partnerDeleted: c.partner.deleted == true,
                                      accepted: c.accepted ?? true, requestedBy: c.requestedBy, partnerAvatar: c.partner.avatar, lastSeen: c.partner.lastSeen)
            }
            for inv in try await api.invitations() {
                db.upsertInvitation(ChatInvitation(id: inv.id, conversationId: inv.conversationId, fromName: inv.fromName ?? "", incoming: inv.toUser == account?.id, expiresAt: inv.expiresAt))
            }
            bump()
        } catch { report(error) }
    }

    func acceptRequest(_ cid: String) async {
        do { try await api.acceptRequest(cid); db.setAccepted(conversationId: cid); bump() } catch { report(error) }
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

    // MARK: sending
    private func newMessage(_ cid: String, text: String, kind: String = "text") -> ChatMessage {
        ChatMessage(id: UUID().uuidString.lowercased(), conversationId: cid, outgoing: true, text: text,
                    sentAt: Int(Date().timeIntervalSince1970), status: .pending, readByMe: true, serverSeq: 0, kind: kind)
    }

    @discardableResult
    func send(_ text: String, in conversationId: String, replyTo: ChatMessage? = nil, forwarded: Bool = false) async -> ChatMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4000, let conv = db.conversation(conversationId) else { return nil }
        var m = newMessage(conversationId, text: trimmed)
        if let r = replyTo { m.replyTo = r.id; m.replyText = String(r.preview.prefix(80)) }
        m.forwarded = forwarded
        if conv.ttl > 0 { m.ttl = conv.ttl; m.expiresAt = Double(m.sentAt + conv.ttl) }   // sender's copy counts from sending
        db.insertMessage(m)
        bump()
        await deliver(m)
        return m
    }

    /// Encrypts an attachment on the phone, uploads the ciphertext, then sends its key inside the E2EE message.
    @discardableResult
    func sendMedia(_ data: Data, mime: String, name: String?, duration: Double? = nil, thumb: Data? = nil, caption: String = "",
                   in conversationId: String, forwarded: Bool = false) async -> Bool {
        guard let conv = db.conversation(conversationId) else { return false }
        guard data.count <= 24 * 1024 * 1024 else { lastError = "too_large"; return false }
        do {
            let (box, key) = try MediaCipher.encrypt(data)
            let up = try await api.uploadMedia(box, conversationId: conversationId)
            let ref = ChatCrypto.MediaRef(id: up.id, key: key, mime: mime, name: name, size: data.count, duration: duration,
                                          thumb: thumb.map { $0.base64EncodedString() })
            var m = newMessage(conversationId, text: caption, kind: "media")
            m.media = ref
            m.forwarded = forwarded
            if conv.ttl > 0 { m.ttl = conv.ttl; m.expiresAt = Double(m.sentAt + conv.ttl) }
            try? cache(data, for: ref)
            db.insertMessage(m)
            bump()
            await deliver(m)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Decrypted attachment file (downloaded and decrypted on first use).
    func mediaURL(_ ref: ChatCrypto.MediaRef) async throws -> URL {
        let file = db.mediaFile(ref.id, ext: Self.ext(for: ref))
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let box = try await api.downloadMedia(ref.id)
        let data = try MediaCipher.decrypt(box, key: ref.key)
        try cache(data, for: ref)
        return file
    }

    private func cache(_ data: Data, for ref: ChatCrypto.MediaRef) throws {
        let file = db.mediaFile(ref.id, ext: Self.ext(for: ref))
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func ext(for ref: ChatCrypto.MediaRef) -> String {
        if let n = ref.name, n.contains("."), let e = n.split(separator: ".").last, e.count <= 5 { return String(e).lowercased() }
        switch ref.mime {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "audio/m4a", "audio/mp4", "audio/x-m4a": return "m4a"
        default: return "bin"
        }
    }

    func forward(_ m: ChatMessage, to cid: String) async {
        if let ref = m.media {
            guard let url = try? await mediaURL(ref), let data = try? Data(contentsOf: url) else { lastError = "media"; return }
            await sendMedia(data, mime: ref.mime, name: ref.name, duration: ref.duration, thumb: ref.thumb.flatMap { Data(base64Encoded: $0) },
                            caption: m.text, in: cid, forwarded: true)
        } else {
            await send(m.text, in: cid, forwarded: true)
        }
    }

    /// Control messages (delete / timer / history / screenshot) are end-to-end encrypted like any message,
    /// kept in the outbox until the server accepts them, and never shown as bubbles.
    private func sendControl(_ what: String, in cid: String, ref: String? = nil, value: Int? = nil) async {
        var m = newMessage(cid, text: what, kind: "ctl")
        m.replyTo = ref; m.ttl = value
        db.insertMessage(m)
        await deliver(m)
    }

    private func systemLine(_ text: String, in cid: String) {
        db.insertMessage(ChatMessage(id: UUID().uuidString.lowercased(), conversationId: cid, outgoing: false, text: text,
                                     sentAt: Int(Date().timeIntervalSince1970), status: .received, readByMe: true, serverSeq: 0, kind: "system"))
    }

    func deleteForEveryone(_ m: ChatMessage) async {
        guard m.outgoing else { return }
        db.markDeleted(id: m.id)
        bump()
        if let mid = m.media?.id { try? await api.deleteMedia(mid) }
        await sendControl("delete", in: m.conversationId, ref: m.id)
    }
    func deleteForMe(_ m: ChatMessage) { db.deleteForMe(id: m.id); bump() }

    func setDisappearing(_ seconds: Int, in cid: String) async {
        db.setTTL(seconds, conversationId: cid)
        systemLine(seconds > 0 ? "⏱ ඔයා disappearing messages \(Self.ttlLabel(seconds)) කළා" : "⏱ ඔයා disappearing messages off කළා", in: cid)
        bump()
        await sendControl("timer", in: cid, value: seconds)
    }

    func setKeepLast(_ n: Int, in cid: String) async {
        db.setKeepLast(n, conversationId: cid)
        systemLine(n > 0 ? "🗂 අන්තිම පණිවිඩ \(n) විතරක් තියාගන්නවා (දෙපැත්තෙම)" : "🗂 සියලු පණිවිඩ තියාගන්නවා", in: cid)
        bump()
        await sendControl("history", in: cid, value: n)
    }

    /// iOS tells the app (not the keyboard) after a screenshot was taken; it cannot prevent it.
    func screenshotTaken(in cid: String) async {
        systemLine("📸 ඔයා screenshot එකක් ගත්තා", in: cid)
        bump()
        await sendControl("screenshot", in: cid)
    }

    func userIsTyping(in cid: String) {
        let now = Date()
        if let last = lastTypingSent[cid], now.timeIntervalSince(last) < 4 { return }
        lastTypingSent[cid] = now
        let a = api
        Task { try? await a.typing(cid) }
    }

    private func envelope(for m: ChatMessage) -> ChatCrypto.Envelope {
        if m.kind == "ctl" {
            return .init(text: "", sentAt: m.sentAt, kind: m.text, ref: m.replyTo, ttl: m.text == "timer" ? m.ttl : nil, keep: m.text == "history" ? m.ttl : nil)
        }
        return .init(text: m.text, sentAt: m.sentAt, kind: m.media != nil ? "media" : nil, ref: m.replyTo, replyText: m.replyText,
                     ttl: m.ttl, media: m.media, forwarded: m.forwarded ? true : nil)
    }

    private func deliver(_ m: ChatMessage, retriedKey: Bool = false) async {
        guard let me = account, let myKey = ChatIdentity.current(), let conv = db.conversation(m.conversationId) else { return }
        do {
            let pub = try ChatCrypto.publicKey(fromBase64: conv.partnerKey)
            let aad = ChatCrypto.aad(messageId: m.id, conversationId: conv.id, senderId: me.id, recipientId: conv.partnerId, sentAt: m.sentAt, recipientKeyVersion: conv.partnerKeyVersion)
            let sealed = try ChatCrypto.seal(envelope(for: m), to: pub, from: myKey, aad: aad)
            let r = try await api.send(id: m.id, conversationId: conv.id, enc: sealed.enc.base64EncodedString(), ciphertext: sealed.ciphertext.base64EncodedString(),
                                       keyVersion: conv.partnerKeyVersion, sentAt: m.sentAt)
            if m.kind == "ctl" { db.deleteForMe(id: m.id) } else { db.setServerSeq(r.seq, id: m.id) }
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

    // MARK: receiving
    /// Pulls new messages and events, decrypts, stores, acknowledges. Safe to call often.
    func sync() async {
        guard isSignedIn, !syncing, let myKey = ChatIdentity.current() else { return }
        syncing = true
        defer { syncing = false }
        purgeExpired()
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
                if let env = try? ChatCrypto.open(.init(enc: enc, ciphertext: ct), with: myKey, from: senderKey, aad: aad), env.sentAt == msg.sentAt {
                    receive(env, id: msg.id, seq: msg.seq, conv: conv)
                } else {
                    db.insertMessage(ChatMessage(id: msg.id, conversationId: msg.conversationId, outgoing: false,
                                                 text: "🔒 මේ පණිවිඩය decrypt කරන්න බැරි වුණා (key එක වෙනස් වෙලා වෙන්න පුළුවන්)",
                                                 sentAt: msg.sentAt, status: .received, readByMe: false, serverSeq: msg.seq, kind: "system"))
                }
                delivered.append(msg.id)
            }
            if let last = r.messages.last { db.setValue(String(last.seq), "cursor.msg") }
            for chunk in stride(from: 0, to: delivered.count, by: 20).map({ Array(delivered[$0..<min($0 + 20, delivered.count)]) }) {
                try? await api.ack(delivered: chunk, read: [])
            }
            for e in r.events { if apply(e) { needsRefresh = true } }
            if let last = r.events.last { db.setValue(String(last.seq), "cursor.evt"); try? await api.ackEvents(upTo: last.seq) }
            if needsRefresh { await refreshConversations() }
            bump()
        } catch { report(error) }
    }

    /// Applies a decrypted envelope from the partner.
    private func receive(_ env: ChatCrypto.Envelope, id: String, seq: Int, conv: ChatConversation) {
        let name = conv.partnerName
        switch env.kind {
        case "delete":
            // The partner may only delete messages THEY sent.
            if let ref = env.ref, let target = db.message(ref), target.conversationId == conv.id, !target.outgoing { db.markDeleted(id: ref) }
        case "timer":
            let s = max(0, env.ttl ?? 0)
            db.setTTL(s, conversationId: conv.id)
            systemLine(s > 0 ? "⏱ \(name) disappearing messages \(Self.ttlLabel(s)) කළා" : "⏱ \(name) disappearing messages off කළා", in: conv.id)
        case "history":
            let n = max(0, env.keep ?? 0)
            db.setKeepLast(n, conversationId: conv.id)
            systemLine(n > 0 ? "🗂 \(name): අන්තිම පණිවිඩ \(n) විතරක් තියාගන්නවා" : "🗂 \(name): සියලු පණිවිඩ තියාගන්නවා", in: conv.id)
        case "screenshot":
            systemLine("📸 \(name) screenshot එකක් ගත්තා", in: conv.id)
        default:
            var m = ChatMessage(id: id, conversationId: conv.id, outgoing: false, text: env.text, sentAt: env.sentAt,
                                status: .received, readByMe: false, serverSeq: seq, kind: env.media != nil ? "media" : "text")
            m.replyTo = env.ref; m.replyText = env.replyText; m.media = env.media; m.forwarded = env.forwarded ?? false
            if let t = env.ttl, t > 0 { m.ttl = t }      // countdown starts when read
            db.insertMessage(m)
        }
        typingUntil[conv.id] = nil
    }

    /// Returns true when the conversation list should be refreshed.
    private func apply(_ e: ChatAPI.Event) -> Bool {
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
                db.setSecret(p["secret"]?.bool ?? false, conversationId: cid)
                db.removeInvitations(conversationId: cid)
            }
        case "key_changed":
            if let uid = p["userId"]?.string, let k = p["kemPub"]?.string, let v = p["keyVersion"]?.int { db.updatePartnerKey(userId: uid, key: k, version: v) }
        case "conversation":
            if let cid = p["conversationId"]?.string, p["partnerDeleted"]?.bool == true { db.markPartnerDeleted(conversationId: cid) }
        case "request":
            return true
        case "accepted":
            if let cid = p["conversationId"]?.string { db.setAccepted(conversationId: cid) }
        case "typing":
            if let cid = p["conversationId"]?.string, Date().timeIntervalSince1970 - Double(p["at"]?.int ?? 0) < 8 {
                typingUntil[cid] = Date().addingTimeInterval(6)
            }
        default: break
        }
        return false
    }

    func markRead(_ conversationId: String) async {
        let ids = db.unreadIncoming(conversationId: conversationId)
        guard !ids.isEmpty else { return }
        db.markReadByMe(ids: ids)          // starts disappearing timers
        bump()
        for chunk in stride(from: 0, to: ids.count, by: 20).map({ Array(ids[$0..<min($0 + 20, ids.count)]) }) {
            try? await api.ack(delivered: [], read: chunk)
        }
    }

    func purgeExpired() {
        if db.deleteExpired() > 0 { bump() }
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

    func bump() { revision &+= 1 }
    private func report(_ e: Error) {
        if let a = e as? ChatAPI.APIError { lastError = a.code } else { lastError = (e as NSError).localizedDescription }
    }
}
