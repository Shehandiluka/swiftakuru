import Foundation
import SQLite3
import CryptoKit

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ChatConversation: Equatable, Identifiable {
    var id: String
    var partnerId: String
    var partnerName: String
    var partnerKey: String          // current X25519 public key (base64)
    var partnerKeyVersion: Int
    var pinnedKey: String           // first key seen (trust on first use) — differs → safety warning
    var secret: Bool
    var hidden: Bool
    var partnerDeleted: Bool
    var updatedAt: Double
    var keyChanged: Bool { !pinnedKey.isEmpty && pinnedKey != partnerKey }
}

struct ChatMessage: Equatable, Identifiable {
    enum Status: String { case pending, sent, delivered, read, failed, received }
    var id: String
    var conversationId: String
    var outgoing: Bool
    var text: String
    var sentAt: Int
    var status: Status
    var readByMe: Bool
    var serverSeq: Int
}

struct ChatInvitation: Equatable, Identifiable {
    var id: String
    var conversationId: String
    var fromName: String
    var incoming: Bool
    var expiresAt: Int
}

/// Local chat database (SQLite in the App Group container when available). Message bodies are encrypted
/// with a device-only AES-256-GCM key from the Keychain; the file itself uses iOS Data Protection.
final class ChatDB {
    static let shared: ChatDB = ChatDB(url: SharedStore.shared.fileURL("chat.sqlite"), key: LocalCipher.key())

    private var db: OpaquePointer?
    private let key: SymmetricKey
    private let lock = NSRecursiveLock()

    init(url: URL, key: SymmetricKey) {
        self.key = key
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK { db = nil }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        exec("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000;")
        exec("""
        CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, partner_id TEXT NOT NULL, partner_name TEXT NOT NULL,
          partner_key TEXT NOT NULL, partner_key_version INTEGER NOT NULL, pinned_key TEXT NOT NULL DEFAULT '', secret INTEGER NOT NULL DEFAULT 0,
          hidden INTEGER NOT NULL DEFAULT 0, partner_deleted INTEGER NOT NULL DEFAULT 0, updated_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, outgoing INTEGER NOT NULL, body BLOB NOT NULL,
          sent_at INTEGER NOT NULL, status TEXT NOT NULL, read_by_me INTEGER NOT NULL DEFAULT 0, server_seq INTEGER NOT NULL DEFAULT 0,
          attempts INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS messages_conv ON messages(conversation_id, sent_at);
        CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, from_name TEXT NOT NULL, incoming INTEGER NOT NULL, expires_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS secret_index (phone_tag TEXT PRIMARY KEY, conversation_id TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT NOT NULL);
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: low level
    @discardableResult
    private func exec(_ sql: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private enum V { case s(String), i(Int), d(Double), b(Data), null }

    @discardableResult
    private func run(_ sql: String, _ args: [V] = []) -> Int {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        guard sqlite3_step(st) == SQLITE_DONE else { return -1 }
        return Int(sqlite3_changes(db))
    }

    private func query(_ sql: String, _ args: [V] = [], _ row: (OpaquePointer) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let s = st else { return }
        defer { sqlite3_finalize(s) }
        bind(s, args)
        while sqlite3_step(s) == SQLITE_ROW { row(s) }
    }

    private func bind(_ st: OpaquePointer?, _ args: [V]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .s(let s): sqlite3_bind_text(st, idx, s, -1, SQLITE_TRANSIENT)
            case .i(let n): sqlite3_bind_int64(st, idx, Int64(n))
            case .d(let d): sqlite3_bind_double(st, idx, d)
            case .b(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(st, idx, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            case .null: sqlite3_bind_null(st, idx)
            }
        }
    }

    private func str(_ s: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
    private func int(_ s: OpaquePointer, _ i: Int32) -> Int { Int(sqlite3_column_int64(s, i)) }
    private func blob(_ s: OpaquePointer, _ i: Int32) -> Data {
        guard let p = sqlite3_column_blob(s, i) else { return Data() }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(s, i)))
    }

    // MARK: kv (sync cursors)
    func value(_ k: String) -> String? { var v: String?; query("SELECT v FROM kv WHERE k=?", [.s(k)]) { v = self.str($0, 0) }; return v }
    func setValue(_ v: String, _ k: String) { run("INSERT INTO kv (k,v) VALUES (?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", [.s(k), .s(v)]) }

    // MARK: conversations
    func upsertConversation(id: String, partnerId: String, partnerName: String, partnerKey: String, keyVersion: Int, secret: Bool, partnerDeleted: Bool = false) {
        run("""
        INSERT INTO conversations (id, partner_id, partner_name, partner_key, partner_key_version, pinned_key, secret, partner_deleted, updated_at)
        VALUES (?1,?2,?3,?4,?5,?4,?6,?7,?8)
        ON CONFLICT(id) DO UPDATE SET partner_name=excluded.partner_name,
          partner_key=CASE WHEN excluded.partner_key<>'' THEN excluded.partner_key ELSE conversations.partner_key END,
          partner_key_version=CASE WHEN excluded.partner_key<>'' THEN excluded.partner_key_version ELSE conversations.partner_key_version END,
          pinned_key=CASE WHEN conversations.pinned_key='' THEN excluded.partner_key ELSE conversations.pinned_key END,
          secret=excluded.secret, partner_deleted=excluded.partner_deleted
        """, [.s(id), .s(partnerId), .s(partnerName), .s(partnerKey), .i(keyVersion), .i(secret ? 1 : 0), .i(partnerDeleted ? 1 : 0), .d(Date().timeIntervalSince1970)])
    }

    func updatePartnerKey(userId: String, key: String, version: Int) {
        run("UPDATE conversations SET partner_key=?, partner_key_version=? WHERE partner_id=?", [.s(key), .i(version), .s(userId)])
    }
    /// The user compared safety numbers and accepts the new key.
    func trustCurrentKey(conversationId: String) { run("UPDATE conversations SET pinned_key=partner_key WHERE id=?", [.s(conversationId)]) }
    func setSecret(_ secret: Bool, conversationId: String) { run("UPDATE conversations SET secret=? WHERE id=?", [.i(secret ? 1 : 0), .s(conversationId)]) }
    func setHidden(_ hidden: Bool, conversationId: String) { run("UPDATE conversations SET hidden=? WHERE id=?", [.i(hidden ? 1 : 0), .s(conversationId)]) }
    func markPartnerDeleted(conversationId: String) { run("UPDATE conversations SET partner_deleted=1 WHERE id=?", [.s(conversationId)]) }
    func touch(conversationId: String) { run("UPDATE conversations SET updated_at=?, hidden=0 WHERE id=?", [.d(Date().timeIntervalSince1970), .s(conversationId)]) }

    func conversations() -> [ChatConversation] {
        var out: [ChatConversation] = []
        query("SELECT id, partner_id, partner_name, partner_key, partner_key_version, pinned_key, secret, hidden, partner_deleted, updated_at FROM conversations ORDER BY updated_at DESC") { s in
            out.append(ChatConversation(id: self.str(s, 0), partnerId: self.str(s, 1), partnerName: self.str(s, 2), partnerKey: self.str(s, 3),
                                        partnerKeyVersion: self.int(s, 4), pinnedKey: self.str(s, 5), secret: self.int(s, 6) == 1,
                                        hidden: self.int(s, 7) == 1, partnerDeleted: self.int(s, 8) == 1, updatedAt: sqlite3_column_double(s, 9)))
        }
        return out
    }
    func conversation(_ id: String) -> ChatConversation? { conversations().first { $0.id == id } }

    func deleteConversationLocally(_ id: String) {
        run("DELETE FROM messages WHERE conversation_id=?", [.s(id)])
        run("DELETE FROM secret_index WHERE conversation_id=?", [.s(id)])
        run("UPDATE conversations SET hidden=1 WHERE id=?", [.s(id)])
    }

    // MARK: messages
    /// Returns false if a message with this id already exists (duplicate / replay).
    @discardableResult
    func insertMessage(_ m: ChatMessage) -> Bool {
        guard let body = LocalCipher.seal(m.text, key: key) else { return false }
        let n = run("INSERT OR IGNORE INTO messages (id, conversation_id, outgoing, body, sent_at, status, read_by_me, server_seq, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                    [.s(m.id), .s(m.conversationId), .i(m.outgoing ? 1 : 0), .b(body), .i(m.sentAt), .s(m.status.rawValue), .i(m.readByMe ? 1 : 0), .i(m.serverSeq), .d(Date().timeIntervalSince1970)])
        if n > 0 { touch(conversationId: m.conversationId) }
        return n > 0
    }

    func hasMessage(_ id: String) -> Bool { var f = false; query("SELECT 1 FROM messages WHERE id=?", [.s(id)]) { _ in f = true }; return f }

    func setStatus(_ status: ChatMessage.Status, ids: [String]) {
        // never move backwards (read → delivered)
        let rank = ["pending": 0, "failed": 0, "sent": 1, "delivered": 2, "read": 3]
        for id in ids {
            query("SELECT status FROM messages WHERE id=? AND outgoing=1", [.s(id)]) { s in
                let cur = self.str(s, 0)
                if (rank[status.rawValue] ?? 0) >= (rank[cur] ?? 0) || cur == "failed" { self.pendingStatus.append(id) }
            }
        }
        for id in pendingStatus { run("UPDATE messages SET status=? WHERE id=?", [.s(status.rawValue), .s(id)]) }
        pendingStatus.removeAll()
    }
    private var pendingStatus: [String] = []

    func setServerSeq(_ seq: Int, id: String) { run("UPDATE messages SET server_seq=?, status=CASE WHEN status IN ('pending','failed') THEN 'sent' ELSE status END WHERE id=?", [.i(seq), .s(id)]) }
    func bumpAttempts(id: String, failed: Bool) { run("UPDATE messages SET attempts=attempts+1, status=CASE WHEN ? THEN 'failed' ELSE status END WHERE id=?", [.i(failed ? 1 : 0), .s(id)]) }

    func messages(conversationId: String, limit: Int? = nil) -> [ChatMessage] {
        var out: [ChatMessage] = []
        let sql = "SELECT id, conversation_id, outgoing, body, sent_at, status, read_by_me, server_seq FROM messages WHERE conversation_id=? ORDER BY sent_at DESC, created_at DESC" + (limit.map { " LIMIT \($0)" } ?? "")
        query(sql, [.s(conversationId)]) { s in
            let text = LocalCipher.open(self.blob(s, 3), key: self.key) ?? "⚠︎"
            out.append(ChatMessage(id: self.str(s, 0), conversationId: self.str(s, 1), outgoing: self.int(s, 2) == 1, text: text, sentAt: self.int(s, 4),
                                   status: ChatMessage.Status(rawValue: self.str(s, 5)) ?? .sent, readByMe: self.int(s, 6) == 1, serverSeq: self.int(s, 7)))
        }
        return out.reversed()
    }

    /// Outgoing messages that still need to be sent (oldest first).
    func outbox() -> [ChatMessage] {
        var ids: [(String, String)] = []
        query("SELECT id, conversation_id FROM messages WHERE outgoing=1 AND status IN ('pending','failed') AND attempts < 20 ORDER BY sent_at") { s in ids.append((self.str(s, 0), self.str(s, 1))) }
        return ids.compactMap { (id, cid) in messages(conversationId: cid).first { $0.id == id } }
    }

    func unreadIncoming(conversationId: String) -> [String] {
        var ids: [String] = []
        query("SELECT id FROM messages WHERE conversation_id=? AND outgoing=0 AND read_by_me=0", [.s(conversationId)]) { ids.append(self.str($0, 0)) }
        return ids
    }
    func unreadCount(conversationId: String) -> Int { unreadIncoming(conversationId: conversationId).count }
    func markReadByMe(ids: [String]) { for id in ids { run("UPDATE messages SET read_by_me=1 WHERE id=?", [.s(id)]) } }

    func lastMessage(conversationId: String) -> ChatMessage? { messages(conversationId: conversationId, limit: 1).last }

    // MARK: invitations
    func upsertInvitation(_ i: ChatInvitation) {
        run("INSERT OR REPLACE INTO invitations (id, conversation_id, from_name, incoming, expires_at) VALUES (?,?,?,?,?)",
            [.s(i.id), .s(i.conversationId), .s(i.fromName), .i(i.incoming ? 1 : 0), .i(i.expiresAt)])
    }
    func removeInvitation(_ id: String) { run("DELETE FROM invitations WHERE id=?", [.s(id)]) }
    func removeInvitations(conversationId: String) { run("DELETE FROM invitations WHERE conversation_id=?", [.s(conversationId)]) }
    func invitations() -> [ChatInvitation] {
        var out: [ChatInvitation] = []
        let now = Int(Date().timeIntervalSince1970)
        query("SELECT id, conversation_id, from_name, incoming, expires_at FROM invitations WHERE expires_at>?", [.i(now)]) { s in
            out.append(ChatInvitation(id: self.str(s, 0), conversationId: self.str(s, 1), fromName: self.str(s, 2), incoming: self.int(s, 3) == 1, expiresAt: self.int(s, 4)))
        }
        return out
    }

    // MARK: secret index (keyboard unlock by phone, offline)
    func indexSecret(phone: String, conversationId: String) {
        run("INSERT OR REPLACE INTO secret_index (phone_tag, conversation_id) VALUES (?,?)", [.s(LocalCipher.phoneTag(phone, key: key)), .s(conversationId)])
    }
    func secretConversation(phone: String) -> String? {
        var id: String?
        query("SELECT conversation_id FROM secret_index WHERE phone_tag=?", [.s(LocalCipher.phoneTag(phone, key: key))]) { id = self.str($0, 0) }
        return id
    }

    func wipeAll() {
        exec("DELETE FROM messages; DELETE FROM conversations; DELETE FROM invitations; DELETE FROM secret_index; DELETE FROM kv;")
    }
    func clearMessages() { exec("DELETE FROM messages;") }
}

/// The keyboard's Secret Chat view shows only the newest messages; older ones stay in the database.
enum LatestMessages {
    static let keyboardLimit = 5
    static func latest(_ all: [ChatMessage], limit: Int = keyboardLimit) -> [ChatMessage] {
        let sorted = all.sorted { ($0.sentAt, $0.serverSeq, $0.id) < ($1.sentAt, $1.serverSeq, $1.id) }
        return Array(sorted.suffix(limit))
    }
}
