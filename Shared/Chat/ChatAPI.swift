import Foundation

/// HTTPS client for the Swift Akuru Chat mailbox (Cloudflare Worker). See chat.swiftlk.com/README.md.
struct ChatAPI {
    static var baseURL = URL(string: "https://swiftakuru-chat.shehandsandeep.workers.dev")!

    struct APIError: Error, Equatable { let status: Int; let code: String }

    struct User: Codable, Equatable {
        let id: String; let displayName: String; let kemPub: String?; let keyVersion: Int; var deleted: Bool?
        var avatar: String?; var lastSeen: Int?; var acceptsRequests: Bool?
    }
    struct Me: Codable, Equatable {
        let id: String; let displayName: String; let discoverable: Bool; let kemPub: String; let keyVersion: Int; let createdAt: Int
        var avatar: String?; var allowRequests: Bool?; var profileVisibility: String?; var lastSeenVisibility: String?; var readReceipts: Bool?
    }
    struct Blocked: Codable, Identifiable { let id: String; let displayName: String }
    struct BlocksResponse: Codable { let blocked: [Blocked] }
    struct MediaUpload: Codable { let id: String; let size: Int }
    struct VerifyResponse: Codable { let token: String; let created: Bool; let user: Me }
    struct LookupResponse: Codable { let found: Bool; let user: User? }
    struct ResolveResponse: Codable { let found: Bool; let conversationId: String?; let user: User? }
    struct Conversation: Codable { let id: String; let secret: Bool; let createdAt: Int; let partner: User; var accepted: Bool?; var requestedBy: String? }
    struct ConversationsResponse: Codable { let conversations: [Conversation] }
    struct NewConversation: Codable { let conversationId: String }
    struct SendResponse: Codable { let seq: Int; let duplicate: Bool }
    struct InboxMessage: Codable { let seq: Int; let id: String; let conversationId: String; let senderId: String; let enc: String; let ciphertext: String; let keyVersion: Int; let sentAt: Int; let serverAt: Int }
    struct Event: Codable { let seq: Int; let type: String; let payload: [String: JSONValue]; let at: Int }
    struct SyncResponse: Codable { let messages: [InboxMessage]; let events: [Event] }
    struct Invitation: Codable { let id: String; let conversationId: String; let fromUser: String; let toUser: String; let createdAt: Int; let expiresAt: Int; let fromName: String? }
    struct InvitationResponse: Codable { let invitation: Invitation }
    struct InvitationsResponse: Codable { let invitations: [Invitation] }
    struct MeResponse: Codable { let user: Me }
    struct OK: Codable { let ok: Bool? }

    var token: String?

    func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil, as: T.Type = T.self) async throws -> T {
        guard let url = URL(string: ChatAPI.baseURL.absoluteString + path) else { throw APIError(status: 0, code: "bad_url") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let t = token { req.setValue("Bearer " + t, forHTTPHeaderField: "authorization") }
        if let b = body { req.httpBody = try JSONSerialization.data(withJSONObject: b) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "http_\(status)"
            throw APIError(status: status, code: code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // auth
    func start(phone: String) async throws { _ = try await request("POST", "/v1/auth/start", body: ["phone": phone], as: OK.self) }
    func verify(phone: String, code: String, name: String, kemPub: String, discoverable: Bool) async throws -> VerifyResponse {
        try await request("POST", "/v1/auth/verify", body: ["phone": phone, "code": code, "displayName": name, "kemPub": kemPub, "discoverable": discoverable, "device": "iPhone"])
    }
    func me() async throws -> Me { try await request("GET", "/v1/me", as: MeResponse.self).user }
    func updateMe(_ fields: [String: Any]) async throws -> Me { try await request("PATCH", "/v1/me", body: fields, as: MeResponse.self).user }
    func setAvatar(_ jpegBase64: String?) async throws -> Me {
        try await request("PUT", "/v1/me/avatar", body: ["avatar": jpegBase64.map { $0 as Any } ?? NSNull()], as: MeResponse.self).user
    }
    func rotateKey(_ kemPub: String) async throws -> Me { try await request("PUT", "/v1/me/keys", body: ["kemPub": kemPub], as: MeResponse.self).user }
    func deleteAccount() async throws { _ = try await request("DELETE", "/v1/me", as: OK.self) }
    func logout() async throws { _ = try await request("POST", "/v1/auth/logout", as: OK.self) }
    func revokeOthers() async throws { _ = try await request("POST", "/v1/auth/revoke-others", as: OK.self) }

    // discovery & conversations
    func lookup(phone: String) async throws -> LookupResponse { try await request("POST", "/v1/lookup", body: ["phone": phone]) }
    func conversations() async throws -> [Conversation] { try await request("GET", "/v1/conversations", as: ConversationsResponse.self).conversations }
    func startConversation(userId: String) async throws -> String { try await request("POST", "/v1/conversations", body: ["userId": userId], as: NewConversation.self).conversationId }
    func hideConversation(_ id: String) async throws { _ = try await request("DELETE", "/v1/conversations/\(id)", as: OK.self) }
    func acceptRequest(_ id: String) async throws { _ = try await request("POST", "/v1/conversations/\(id)/accept", as: OK.self) }
    func typing(_ id: String) async throws { _ = try await request("POST", "/v1/conversations/\(id)/typing", as: OK.self) }

    // encrypted attachments
    func uploadMedia(_ box: Data, conversationId: String) async throws -> MediaUpload {
        guard let url = URL(string: ChatAPI.baseURL.absoluteString + "/v1/media?conversationId=" + conversationId) else { throw APIError(status: 0, code: "bad_url") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 120
        req.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        if let t = token { req.setValue("Bearer " + t, forHTTPHeaderField: "authorization") }
        let (data, resp) = try await URLSession.shared.upload(for: req, from: box)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, code: status == 413 ? "too_large" : "http_\(status)") }
        return try JSONDecoder().decode(MediaUpload.self, from: data)
    }
    func downloadMedia(_ id: String) async throws -> Data {
        guard let url = URL(string: ChatAPI.baseURL.absoluteString + "/v1/media/" + id) else { throw APIError(status: 0, code: "bad_url") }
        var req = URLRequest(url: url); req.timeoutInterval = 120
        if let t = token { req.setValue("Bearer " + t, forHTTPHeaderField: "authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, code: "http_\(status)") }
        return data
    }
    func deleteMedia(_ id: String) async throws { _ = try await request("DELETE", "/v1/media/\(id)", as: OK.self) }

    // messages
    func send(id: String, conversationId: String, enc: String, ciphertext: String, keyVersion: Int, sentAt: Int) async throws -> SendResponse {
        try await request("POST", "/v1/messages", body: ["id": id, "conversationId": conversationId, "enc": enc, "ciphertext": ciphertext, "keyVersion": keyVersion, "sentAt": sentAt])
    }
    func sync(after: Int, events: Int) async throws -> SyncResponse { try await request("GET", "/v1/sync?after=\(after)&events=\(events)") }
    func ack(delivered: [String], read: [String]) async throws { _ = try await request("POST", "/v1/messages/ack", body: ["delivered": delivered, "read": read], as: OK.self) }
    func ackEvents(upTo: Int) async throws { _ = try await request("POST", "/v1/events/ack", body: ["upTo": upTo], as: OK.self) }

    // secret chat
    func invite(conversationId: String) async throws -> Invitation { try await request("POST", "/v1/secret/invite", body: ["conversationId": conversationId], as: InvitationResponse.self).invitation }
    func invitations() async throws -> [Invitation] { try await request("GET", "/v1/secret/invitations", as: InvitationsResponse.self).invitations }
    func respond(invitationId: String, accept: Bool) async throws { _ = try await request("POST", "/v1/secret/respond", body: ["invitationId": invitationId, "accept": accept], as: OK.self) }
    func leaveSecret(conversationId: String) async throws { _ = try await request("POST", "/v1/secret/leave", body: ["conversationId": conversationId], as: OK.self) }
    func resolveSecret(phone: String) async throws -> ResolveResponse { try await request("POST", "/v1/secret/resolve", body: ["phone": phone]) }

    // safety
    func block(userId: String) async throws { _ = try await request("POST", "/v1/blocks", body: ["userId": userId], as: OK.self) }
    func unblock(userId: String) async throws { _ = try await request("DELETE", "/v1/blocks/\(userId)", as: OK.self) }
    func blocked() async throws -> [Blocked] { try await request("GET", "/v1/blocks", as: BlocksResponse.self).blocked }
    func report(userId: String, conversationId: String?, reason: String) async throws {
        var b: [String: Any] = ["userId": userId, "reason": reason]
        if let c = conversationId { b["conversationId"] = c }
        _ = try await request("POST", "/v1/reports", body: b, as: OK.self)
    }
}

/// Minimal JSON value for event payloads.
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var int: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var strings: [String] { if case .array(let a) = self { return a.compactMap { $0.string } }; return [] }
}
