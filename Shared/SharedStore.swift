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

    /// SideStore / AltStore re-sign the app with a free Apple ID and rename the App Group
    /// (e.g. "group.store.swiftpaypos.swiftakuru.ABCDE12345"). They write the real names into
    /// Info.plist as "ALTAppGroups", so look there first (in the app and, from the keyboard, in the host app).
    static var groupCandidates: [String] {
        var bundles = [Bundle.main]
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex", let host = Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent()) { bundles.append(host) }
        var out: [String] = []
        for b in bundles {
            for g in (b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? [] where !out.contains(g) { out.append(g) }
        }
        if !out.contains(appGroup) { out.append(appGroup) }
        return out
    }

    private(set) var activeGroup: String?

    private init() {
        let found = SharedStore.groupCandidates.lazy.compactMap { g in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g).map { (g, $0) }
        }.first
        if let f = found {
            let group = f.0, url = f.1
            containerURL = url
            hasAppGroup = true
            activeGroup = group
            defaults = UserDefaults(suiteName: group) ?? .standard
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            containerURL = base.appendingPathComponent("SwiftAkuru", isDirectory: true)
            hasAppGroup = false
            defaults = .standard
        }
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        if hasAppGroup { migrateLocalData() }
        defaults.register(defaults: [
            K.layout: "singlish", K.theme: "graphite", K.sound: true, K.haptics: true, K.autoCap: true, K.autocorrect: true,
            K.doubleSpace: true, K.livePreview: true, K.keyHints: true, K.numberRow: false, K.aiProvider: "gemini",
            K.aiModelGemini: "gemini-2.5-flash", K.aiModelOpenAI: "gpt-4.1-mini", K.clipboardMax: 40, K.keyHeight: 50.0,
            K.emojiSuggest: true, K.learnWords: true, K.clipAuto: false,
        ])
    }

    /// When an update starts using the App Group (e.g. after moving to SideStore), carry over what was
    /// saved locally before: learned words, clipboard, photo background and settings. Runs once.
    private func migrateLocalData() {
        let flag = "migratedLocal." + (Bundle.main.bundleIdentifier ?? "app")
        guard !defaults.bool(forKey: flag) else { return }
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SwiftAkuru", isDirectory: true),
           let files = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for f in files {
                let dest = containerURL.appendingPathComponent(f.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: f, to: dest) }
            }
        }
        let keys = [K.layout, K.theme, K.sound, K.haptics, K.autoCap, K.autocorrect, K.doubleSpace, K.livePreview, K.keyHints, K.numberRow,
                    K.aiProvider, K.aiKeyGemini, K.aiKeyOpenAI, K.aiModelGemini, K.aiModelOpenAI, K.clipboardMax, K.keyHeight,
                    K.shortcuts, K.emojiSuggest, K.learnWords, K.recentEmoji, K.clipAuto]
        for k in keys where defaults.object(forKey: k) == nil {
            if let v = UserDefaults.standard.object(forKey: k) { defaults.set(v, forKey: k) }
        }
        defaults.set(true, forKey: flag)
    }

    enum K {
        static let layout = "layout", theme = "theme", sound = "sound", haptics = "haptics", autoCap = "autoCap", autocorrect = "autocorrect"
        static let doubleSpace = "doubleSpace", livePreview = "livePreview", keyHints = "keyHints", numberRow = "numberRow"
        static let aiProvider = "aiProvider", aiKeyGemini = "aiKeyGemini", aiKeyOpenAI = "aiKeyOpenAI", aiModelGemini = "aiModelGemini", aiModelOpenAI = "aiModelOpenAI"
        static let clipboardMax = "clipboardMax", keyHeight = "keyHeight", shortcuts = "shortcuts", emojiSuggest = "emojiSuggest", learnWords = "learnWords"
        static let recentEmoji = "recentEmoji", customBg = "customBg", clipAuto = "clipAuto"
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
