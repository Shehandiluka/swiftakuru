import Foundation

/// Settings shared by the app and the keyboard. Uses the App Group when it is available
/// (paid developer account); otherwise each target keeps its own copy — the keyboard has
/// its own settings panel so it works fully on its own (free Apple ID sideloading).
final class SharedStore {
    static let appGroup = "group.store.swiftpaypos.swiftakuru"
    static let shared = SharedStore()

    let defaults: UserDefaults
    let containerURL: URL
    let hasAppGroup: Bool

    private init() {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup) {
            containerURL = url
            hasAppGroup = true
            defaults = UserDefaults(suiteName: SharedStore.appGroup) ?? .standard
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            containerURL = base.appendingPathComponent("SwiftAkuru", isDirectory: true)
            hasAppGroup = false
            defaults = .standard
        }
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defaults.register(defaults: [
            K.layout: "singlish", K.theme: "swift", K.sound: true, K.haptics: true, K.autoCap: true, K.autocorrect: true,
            K.doubleSpace: true, K.livePreview: true, K.keyHints: true, K.numberRow: false, K.aiProvider: "gemini",
            K.aiModelGemini: "gemini-2.5-flash", K.aiModelOpenAI: "gpt-4.1-mini", K.clipboardMax: 40, K.keyHeight: 53.0,
            K.emojiSuggest: true, K.learnWords: true,
        ])
    }

    enum K {
        static let layout = "layout", theme = "theme", sound = "sound", haptics = "haptics", autoCap = "autoCap", autocorrect = "autocorrect"
        static let doubleSpace = "doubleSpace", livePreview = "livePreview", keyHints = "keyHints", numberRow = "numberRow"
        static let aiProvider = "aiProvider", aiKeyGemini = "aiKeyGemini", aiKeyOpenAI = "aiKeyOpenAI", aiModelGemini = "aiModelGemini", aiModelOpenAI = "aiModelOpenAI"
        static let clipboardMax = "clipboardMax", keyHeight = "keyHeight", shortcuts = "shortcuts", emojiSuggest = "emojiSuggest", learnWords = "learnWords"
        static let recentEmoji = "recentEmoji", customBg = "customBg"
    }

    subscript(bool key: String) -> Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
    subscript(string key: String) -> String {
        get { defaults.string(forKey: key) ?? "" }
        set { defaults.set(newValue, forKey: key) }
    }
    var layout: String { get { self[string: K.layout] } set { self[string: K.layout] = newValue } }
    var themeId: String { get { self[string: K.theme] } set { self[string: K.theme] = newValue } }
    var keyHeight: Double { get { defaults.double(forKey: K.keyHeight) } set { defaults.set(newValue, forKey: K.keyHeight) } }
    var clipboardMax: Int { max(5, defaults.integer(forKey: K.clipboardMax)) }

    /// text shortcuts: "@@" → "me@mail.com"
    var shortcuts: [String: String] {
        get { (defaults.dictionary(forKey: K.shortcuts) as? [String: String]) ?? ["@@": "contact@swiftpaypos.store", "omw": "On my way!", "gm": "Good morning! ☀️", "gn": "Good night 🌙", "thx": "ස්තුතියි! 🙏"] }
        set { defaults.set(newValue, forKey: K.shortcuts) }
    }
    var recentEmoji: [String] {
        get { defaults.stringArray(forKey: K.recentEmoji) ?? [] }
        set { defaults.set(Array(newValue.prefix(32)), forKey: K.recentEmoji) }
    }

    var aiKey: String {
        self[string: K.aiProvider] == "openai" ? self[string: K.aiKeyOpenAI] : self[string: K.aiKeyGemini]
    }

    func fileURL(_ name: String) -> URL { containerURL.appendingPathComponent(name) }

    var customBackgroundURL: URL { fileURL("keyboard-background.jpg") }
}
