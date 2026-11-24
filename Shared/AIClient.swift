import Foundation

/// Tiny client for Google Gemini (free API key from aistudio.google.com) or OpenAI.
enum AIClient {
    enum AIError: LocalizedError {
        case noKey, http(Int, String), empty
        var errorDescription: String? {
            switch self {
            case .noKey: return "AI key එකක් නැහැ. Settings → AI වල Gemini key එක දාන්න."
            case .http(let c, let m): return "AI error \(c): \(m)"
            case .empty: return "AI එකෙන් උත්තරයක් ආවේ නැහැ."
            }
        }
    }

    enum Action: String, CaseIterable {
        case toEnglish, toSinhala, fix, formal, friendly, shorter, reply, ask, emoji, toTamil
        var title: String {
            switch self {
            case .toEnglish: return "🇬🇧 English"
            case .toSinhala: return "🇱🇰 සිංහල"
            case .toTamil: return "தமிழ்"
            case .fix: return "✓ Grammar fix"
            case .formal: return "👔 Formal"
            case .friendly: return "😊 Friendly"
            case .shorter: return "✂️ Shorter"
            case .reply: return "💬 Reply ideas"
            case .ask: return "✨ Ask AI"
            case .emoji: return "🎉 + Emoji"
            }
        }
        func prompt(_ text: String) -> String {
            let rule = "Return ONLY the final text, no quotes, no explanations."
            switch self {
            case .toEnglish: return "Translate this (it may be Sinhala, Singlish or mixed) into natural English. \(rule)\n\n\(text)"
            case .toSinhala: return "Translate this into natural, everyday Sinhala written in Sinhala Unicode script. \(rule)\n\n\(text)"
            case .toTamil: return "Translate this into natural Tamil in Tamil script. \(rule)\n\n\(text)"
            case .fix: return "Fix the spelling and grammar of this text, keep its language (Sinhala stays Sinhala, English stays English) and meaning. \(rule)\n\n\(text)"
            case .formal: return "Rewrite this text in a polite, professional tone, same language. \(rule)\n\n\(text)"
            case .friendly: return "Rewrite this text in a warm, friendly, casual tone, same language. \(rule)\n\n\(text)"
            case .shorter: return "Make this text shorter and clearer, same language. \(rule)\n\n\(text)"
            case .reply: return "Write 3 short alternative replies to this message, in the same language as the message, one per line, without numbering. \(rule)\n\nMessage:\n\(text)"
            case .ask: return "Answer helpfully and concisely. If the question is in Sinhala or Singlish, answer in Sinhala script.\n\n\(text)"
            case .emoji: return "Add a few fitting emojis to this text without changing the words. \(rule)\n\n\(text)"
            }
        }
    }

    static func run(_ action: Action, text: String) async throws -> String {
        try await complete(action.prompt(text))
    }

    static func complete(_ prompt: String) async throws -> String {
        try await complete(prompt, json: false, audio: nil)
    }

    /// - json: ask the model for a JSON object only
    /// - audio: a voice message (Gemini reads it directly; OpenAI transcribes it first)
    static func complete(_ prompt: String, json wantJSON: Bool, audio: (data: Data, mime: String)?) async throws -> String {
        let st = SharedStore.shared
        var prompt = prompt
        if let a = audio, st[string: SharedStore.K.aiProvider] == "openai" {
            let heard = try await transcribeOpenAI(a.data, mime: a.mime)
            prompt += "\n\nVOICE MESSAGE TRANSCRIPT (from speech recognition):\n" + heard
        }
        let key = st.aiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noKey }
        var req: URLRequest
        let openai = st[string: SharedStore.K.aiProvider] == "openai"
        if openai {
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var body: [String: Any] = ["model": st[string: SharedStore.K.aiModelOpenAI], "messages": [["role": "user", "content": prompt]], "temperature": 0.3]
            if wantJSON { body["response_format"] = ["type": "json_object"] }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            let model = st[string: SharedStore.K.aiModelGemini].isEmpty ? "gemini-2.5-flash" : st[string: SharedStore.K.aiModelGemini]
            req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var parts: [[String: Any]] = []
            if let a = audio { parts.append(["inline_data": ["mime_type": a.mime, "data": a.data.base64EncodedString()]]) }
            parts.append(["text": prompt])
            var gen: [String: Any] = ["temperature": 0.3]
            if wantJSON { gen["responseMimeType"] = "application/json" }
            let body: [String: Any] = ["contents": [["role": "user", "parts": parts]], "generationConfig": gen]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = audio == nil ? 30 : 90
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard code == 200 else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(code, String(msg.prefix(160)))
        }
        var text: String?
        if openai {
            text = (((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String)
        } else {
            let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { throw AIError.empty }
        return t
    }

    /// OpenAI speech-to-text for voice messages.
    static func transcribeOpenAI(_ data: Data, mime: String) async throws -> String {
        let key = SharedStore.shared.aiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noKey }
        let ext = Translator.fileExtension(forMime: mime)
        let boundary = "SA-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", "gpt-4o-mini-transcribe")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        let (out, resp) = try await URLSession.shared.upload(for: req, from: body)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any] ?? [:]
        guard code == 200 else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw AIError.http(code, String(msg.prefix(160)))
        }
        guard let t = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { throw AIError.empty }
        return t
    }
}
