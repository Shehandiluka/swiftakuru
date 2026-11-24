import Foundation

/// Translate any message (text or voice) into your language, then translate your reply back into theirs.
enum Translator {
    struct Language: Hashable, Codable {
        let code: String      // ISO 639-1 (BCP-47 for a few)
        let name: String      // English name, used in prompts
        let native: String    // shown on buttons
        var label: String { native == name ? name : "\(native) · \(name)" }
    }

    static let all: [Language] = [
        .init(code: "si", name: "Sinhala", native: "සිංහල"),
        .init(code: "en", name: "English", native: "English"),
        .init(code: "ta", name: "Tamil", native: "தமிழ்"),
        .init(code: "he", name: "Hebrew", native: "עברית"),
        .init(code: "ar", name: "Arabic", native: "العربية"),
        .init(code: "hi", name: "Hindi", native: "हिन्दी"),
        .init(code: "ko", name: "Korean", native: "한국어"),
        .init(code: "ja", name: "Japanese", native: "日本語"),
        .init(code: "zh", name: "Chinese (Simplified)", native: "中文"),
        .init(code: "ru", name: "Russian", native: "Русский"),
        .init(code: "uk", name: "Ukrainian", native: "Українська"),
        .init(code: "fr", name: "French", native: "Français"),
        .init(code: "de", name: "German", native: "Deutsch"),
        .init(code: "it", name: "Italian", native: "Italiano"),
        .init(code: "es", name: "Spanish", native: "Español"),
        .init(code: "pt", name: "Portuguese", native: "Português"),
        .init(code: "nl", name: "Dutch", native: "Nederlands"),
        .init(code: "pl", name: "Polish", native: "Polski"),
        .init(code: "ro", name: "Romanian", native: "Română"),
        .init(code: "tr", name: "Turkish", native: "Türkçe"),
        .init(code: "fa", name: "Persian", native: "فارسی"),
        .init(code: "ur", name: "Urdu", native: "اردو"),
        .init(code: "bn", name: "Bengali", native: "বাংলা"),
        .init(code: "ne", name: "Nepali", native: "नेपाली"),
        .init(code: "dv", name: "Dhivehi", native: "ދިވެހި"),
        .init(code: "ml", name: "Malayalam", native: "മലയാളം"),
        .init(code: "th", name: "Thai", native: "ไทย"),
        .init(code: "vi", name: "Vietnamese", native: "Tiếng Việt"),
        .init(code: "ms", name: "Malay", native: "Bahasa Melayu"),
        .init(code: "id", name: "Indonesian", native: "Bahasa Indonesia"),
        .init(code: "fil", name: "Filipino", native: "Filipino"),
        .init(code: "el", name: "Greek", native: "Ελληνικά"),
    ]

    static func language(_ code: String?) -> Language? {
        guard let c = code?.lowercased(), !c.isEmpty else { return nil }
        return all.first { $0.code == c } ?? all.first { c.hasPrefix($0.code + "-") } ?? (c == "iw" ? language("he") : nil)
    }
    static func language(named n: String) -> Language? {
        let l = n.lowercased()
        return all.first { $0.name.lowercased() == l || $0.native.lowercased() == l }
    }

    // MARK: remembered choices
    private static let myKey = "translateMyLang", recentKey = "translateRecent"
    /// The language messages are translated into (default Sinhala).
    static var myLanguage: Language {
        get { language(SharedStore.shared.defaults.string(forKey: myKey)) ?? all[0] }
        set { SharedStore.shared.defaults.set(newValue.code, forKey: myKey); touch(newValue) }
    }
    /// Most recently used languages first (shown at the top of every language list).
    static var recent: [Language] {
        (SharedStore.shared.defaults.stringArray(forKey: recentKey) ?? []).compactMap { language($0) }
    }
    static func touch(_ l: Language) {
        var codes = SharedStore.shared.defaults.stringArray(forKey: recentKey) ?? []
        codes.removeAll { $0 == l.code }
        codes.insert(l.code, at: 0)
        SharedStore.shared.defaults.set(Array(codes.prefix(8)), forKey: recentKey)
    }
    /// Every language, the last used ones on top.
    static var ordered: [Language] {
        let r = recent
        return r + all.filter { !r.contains($0) }
    }

    // MARK: results
    struct Result: Equatable {
        var transcript: String?       // voice messages: what was said
        var source: Language?         // detected language of the message
        var sourceName: String        // detected language name as the model said it
        var translation: String
    }

    static func translate(_ text: String, to target: Language) async throws -> Result {
        let prompt = """
        You are a translator for chat messages. Detect the language of MESSAGE and translate it into \(target.name) \
        (write \(target.name) in its own script; Sinhala must be in Sinhala Unicode script, natural everyday Sinhala). \
        If MESSAGE is Singlish (Sinhala written in Latin letters) treat it as Sinhala. Keep emojis, names and numbers. \
        Respond with JSON only: {"language": "<English name of the detected language>", "code": "<ISO 639-1 code>", "translation": "<the translation>"}

        MESSAGE:
        \(text)
        """
        let out = try await AIClient.complete(prompt, json: true, audio: nil)
        return parse(out, fallbackTranslation: out)
    }

    static func translateVoice(_ audio: Data, mime: String, to target: Language) async throws -> Result {
        let prompt = """
        This is a voice message from a chat. 1) Transcribe exactly what is said, in the original language and script. \
        2) Detect the language. 3) Translate it into \(target.name) (in its own script; Sinhala in Sinhala Unicode, natural everyday Sinhala). \
        Respond with JSON only: {"transcript": "<what was said>", "language": "<English name of the detected language>", "code": "<ISO 639-1 code>", "translation": "<the translation>"}
        """
        let out = try await AIClient.complete(prompt, json: true, audio: (audio, mime))
        return parse(out, fallbackTranslation: out)
    }

    /// Your reply (Sinhala, Singlish or English) → their language, ready to send.
    static func reply(_ text: String, to target: Language, context: String? = nil) async throws -> String {
        var prompt = """
        Translate MY REPLY into \(target.name), written in \(target.name)'s own script, as a natural, friendly chat message \
        (the way a native speaker would text it). MY REPLY may be Sinhala, Singlish (Sinhala in Latin letters) or English. \
        Keep emojis, names and numbers. Return ONLY the translated message, no quotes, no explanations.
        """
        if let c = context, !c.isEmpty { prompt += "\n\nThe message I am replying to (for context only, do not translate it):\n\(c.prefix(1500))" }
        prompt += "\n\nMY REPLY:\n\(text)"
        touch(target)
        return try await AIClient.complete(prompt, json: false, audio: nil)
    }

    static func parse(_ raw: String, fallbackTranslation: String) -> Result {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let r = s.range(of: "```", options: .backwards) { s = String(s[..<r.lowerBound]) }
        }
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b { s = String(s[a...b]) }
        guard let d = s.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let tr = (j["translation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !tr.isEmpty else {
            return Result(transcript: nil, source: nil, sourceName: "", translation: fallbackTranslation)
        }
        let name = (j["language"] as? String) ?? ""
        let lang = language(j["code"] as? String) ?? language(named: name)
        let tx = (j["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(transcript: (tx?.isEmpty ?? true) ? nil : tx, source: lang, sourceName: lang?.name ?? name, translation: tr)
    }

    static func mime(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "opus", "ogg", "oga": return "audio/ogg"
        case "m4a", "mp4", "aac": return "audio/mp4"
        case "mp3", "mpeg": return "audio/mp3"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "aiff", "aif": return "audio/aiff"
        case "caf": return "audio/x-caf"
        case "amr": return "audio/amr"
        case "webm": return "audio/webm"
        default: return "audio/mp4"
        }
    }
    static func fileExtension(forMime m: String) -> String {
        switch m {
        case "audio/ogg": return "ogg"
        case "audio/mp3": return "mp3"
        case "audio/wav": return "wav"
        case "audio/flac": return "flac"
        case "audio/webm": return "webm"
        default: return "m4a"
        }
    }
}
