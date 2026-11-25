import Foundation
import Security

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
            K.emojiSuggest: true, K.learnWords: true, K.clipAuto: false, K.nameGlow: true, K.smartTouch: true, K.seasonFx: true,
        ])
        restoreAIKeys()
        restoreSettings()
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
        static let recentEmoji = "recentEmoji", customBg = "customBg", clipAuto = "clipAuto", nameGlow = "nameGlow", smartTouch = "smartTouch", seasonFx = "seasonFx"
    }

    subscript(bool key: String) -> Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key); settingChanged(key) }
    }
    subscript(string key: String) -> String {
        get { defaults.string(forKey: key) ?? "" }
        set {
            defaults.set(newValue, forKey: key)
            if SharedStore.secretKeys.contains(key) { keychainSave(newValue, key) }
            settingChanged(key)
        }
    }
    var layout: String { get { self[string: K.layout] } set { self[string: K.layout] = newValue } }
    var themeId: String { get { self[string: K.theme] } set { self[string: K.theme] = newValue } }
    var keyHeight: Double { get { defaults.double(forKey: K.keyHeight) } set { defaults.set(newValue, forKey: K.keyHeight); settingChanged(K.keyHeight) } }
    var clipboardMax: Int { max(5, defaults.integer(forKey: K.clipboardMax)) }

    /// text shortcuts: "@@" → "me@mail.com"
    var shortcuts: [String: String] {
        get { (defaults.dictionary(forKey: K.shortcuts) as? [String: String]) ?? ["@@": "contact@swiftpaypos.store", "omw": "On my way!", "gm": "Good morning! ☀️", "gn": "Good night 🌙", "thx": "ස්තුතියි! 🙏"] }
        set { defaults.set(newValue, forKey: K.shortcuts); settingChanged(K.shortcuts) }
    }
    var recentEmoji: [String] {
        get { defaults.stringArray(forKey: K.recentEmoji) ?? [] }
        set { defaults.set(Array(newValue.prefix(32)), forKey: K.recentEmoji) }
    }

    // MARK: AI keys survive updates and reinstalls
    /// The API keys are also kept in the Keychain (shared App Group access group and the app's own),
    /// because a re-signed update can come with a new App Group, which starts with empty settings.
    private static let keyService = "store.swiftpaypos.swiftakuru.ai"
    private func keychainQueries(_ account: String) -> [[String: Any]] {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: SharedStore.keyService,
                                   kSecAttrAccount as String: account]
        var out: [[String: Any]] = []
        if let g = activeGroup { var q = base; q[kSecAttrAccessGroup as String] = g; out.append(q) }
        out.append(base)
        return out
    }
    private func keychainSave(_ value: String, _ account: String) {
        for q in keychainQueries(account) {
            if value.isEmpty { SecItemDelete(q as CFDictionary); continue }
            let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
            var st = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
            if st == errSecItemNotFound {
                var add = q; for (k, v) in attrs { add[k] = v }
                st = SecItemAdd(add as CFDictionary, nil)
            }
            defaults.set(Int(st), forKey: "diag.keychain")   // 0 = OK (shown in Keyboard health)
        }
    }
    private func keychainLoad(_ account: String) -> String? {
        for var q in keychainQueries(account) {
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
               let v = String(data: d, encoding: .utf8), !v.isEmpty { return v }
        }
        return nil
    }
    static let secretKeys = [K.aiKeyGemini, K.aiKeyOpenAI]

    /// Every keyboard setting that should survive an update (AI keys are kept separately above).
    static let settingKeys = [K.layout, K.theme, K.sound, K.haptics, K.autoCap, K.autocorrect, K.doubleSpace, K.livePreview, K.keyHints,
                              K.numberRow, K.aiProvider, K.aiModelGemini, K.aiModelOpenAI, K.clipboardMax, K.keyHeight, K.shortcuts,
                              K.emojiSuggest, K.learnWords, K.clipAuto, K.nameGlow, K.smartTouch, K.seasonFx]
    private static let settingsAccount = "settings.v1"
    private static let settingsMarker = "settingsRestoreChecked"

    private var backupWork: DispatchWorkItem?
    /// Any setting changed → save a backup copy shortly after (debounced).
    private func settingChanged(_ key: String) {
        guard SharedStore.settingKeys.contains(key) else { return }
        backupWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.backupSettings() }
        backupWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    /// Backup copies of the settings, so an update never resets them. Kept in 3 places, because which ones survive
    /// depends on how the app was installed: the Keychain, this app's own (private) settings and a file.
    private var backupFiles: [URL] {
        var out = [containerURL.appendingPathComponent("settings-backup.plist")]
        if let a = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            out.append(a.appendingPathComponent("SwiftAkuru-settings-backup.plist"))
        }
        return out
    }
    func backupSettings() {
        var snap: [String: Any] = [:]
        for k in SharedStore.settingKeys { if let v = defaults.object(forKey: k) { snap[k] = v } }
        snap["savedAt"] = Date().timeIntervalSince1970
        guard PropertyListSerialization.propertyList(snap, isValidFor: .binary),
              let d = try? PropertyListSerialization.data(fromPropertyList: snap, format: .binary, options: 0) else { return }
        keychainSave(d.base64EncodedString(), SharedStore.settingsAccount)
        UserDefaults.standard.set(d, forKey: "settingsSnapshot")
        for u in backupFiles {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: u, options: .atomic)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: "diag.backupAt")
    }
    private func restoreSettings() {
        defer { defaults.set(true, forKey: SharedStore.settingsMarker) }
        guard !defaults.bool(forKey: SharedStore.settingsMarker) else { return }   // these settings were already in use
        // a fresh settings store (new install or new App Group after an update): bring back the newest backup
        var blobs: [Data] = []
        if let b = keychainLoad(SharedStore.settingsAccount), let d = Data(base64Encoded: b) { blobs.append(d) }
        if let d = UserDefaults.standard.data(forKey: "settingsSnapshot") { blobs.append(d) }
        for u in backupFiles { if let d = try? Data(contentsOf: u) { blobs.append(d) } }
        let snaps = blobs.compactMap { (try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)) as? [String: Any] }
        guard let best = snaps.max(by: { ($0["savedAt"] as? Double ?? 0) < ($1["savedAt"] as? Double ?? 0) }) else { return }
        for (k, v) in best where SharedStore.settingKeys.contains(k) { defaults.set(v, forKey: k) }
        defaults.set(Date().timeIntervalSince1970, forKey: "diag.restoredAt")
    }
    /// Call after an API key changes (the app's settings screen writes defaults directly).
    func backupAIKeys() {
        for k in SharedStore.secretKeys { keychainSave(self[string: k], k) }
        defaults.set(self[string: K.aiProvider], forKey: K.aiProvider)
    }
    /// Empty settings (new App Group after an update) → bring the saved keys back from the Keychain.
    private func restoreAIKeys() {
        // Keychain is only read when these settings are new (fresh install / new App Group) — never on every launch,
        // because the keyboard must start instantly.
        let marker = "aiRestoreChecked"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)
        var restored = false
        for k in SharedStore.secretKeys where (defaults.string(forKey: k) ?? "").isEmpty {
            if let v = keychainLoad(k) { defaults.set(v, forKey: k); restored = true }
        }
        if restored, (defaults.string(forKey: K.aiKeyGemini) ?? "").isEmpty { defaults.set("openai", forKey: K.aiProvider) }
    }

    var aiKey: String {
        self[string: K.aiProvider] == "openai" ? self[string: K.aiKeyOpenAI] : self[string: K.aiKeyGemini]
    }

    func fileURL(_ name: String) -> URL { containerURL.appendingPathComponent(name) }

    var customBackgroundURL: URL { fileURL("keyboard-background.jpg") }
}
