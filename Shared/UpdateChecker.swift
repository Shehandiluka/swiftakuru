import Foundation

/// Published by GitHub Actions with every build (see .github/workflows/build.yml).
struct AppUpdate: Codable, Equatable {
    let version: String
    let build: Int
    let date: String?
    let notes: [String]?
    let ipa: String
    let size: Int?
}

/// Checks GitHub Releases for a newer Swift Akuru build. Used by the app and by the keyboard.
enum UpdateChecker {
    static let feed = URL(string: "https://github.com/Shehandiluka/swiftakuru/releases/latest/download/update.json")!
    static let altSource = "https://github.com/Shehandiluka/swiftakuru/releases/latest/download/altstore.json"
    static let releasesPage = URL(string: "https://github.com/Shehandiluka/swiftakuru/releases/latest")!

    /// SideStore / AltStore add ALTDeviceID to Info.plist when they sign an app.
    static var installedWithSideStore: Bool {
        var bundles = [Bundle.main]
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex", let host = Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent()) { bundles.append(host) }
        return bundles.contains { $0.object(forInfoDictionaryKey: "ALTDeviceID") != nil }
    }

    static var currentBuild: Int { Int((Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0") ?? 0 }
    static var currentVersion: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0" }

    /// Returns the update if one is newer than this build. Checks the network at most every 6 hours unless forced.
    static func check(force: Bool = false) async -> AppUpdate? {
        let d = SharedStore.shared.defaults
        if !force, let last = d.object(forKey: "updLastCheck") as? Date, Date().timeIntervalSince(last) < 6 * 3600 { return cached() }
        var req = URLRequest(url: feed)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        guard let result = try? await URLSession.shared.data(for: req) else { return cached() }
        let (data, resp) = result
        guard (resp as? HTTPURLResponse)?.statusCode == 200, (try? JSONDecoder().decode(AppUpdate.self, from: data)) != nil else { return cached() }
        d.set(Date(), forKey: "updLastCheck")
        d.set(data, forKey: "updFeed")
        return cached()
    }

    static func cached() -> AppUpdate? {
        guard let data = SharedStore.shared.defaults.data(forKey: "updFeed"), let u = try? JSONDecoder().decode(AppUpdate.self, from: data), u.build > currentBuild else { return nil }
        // only ever install from our own GitHub releases over HTTPS
        guard let ipa = URL(string: u.ipa), ipa.scheme == "https", ipa.host == "github.com",
              ipa.path.lowercased().hasPrefix("/shehandiluka/swiftakuru/releases/") else { return nil }
        return u
    }

    static func sideStoreURL(_ u: AppUpdate) -> URL? { URL(string: "sidestore://install?url=" + (u.ipa.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? u.ipa)) }
    static func altStoreURL(_ u: AppUpdate) -> URL? { URL(string: "altstore://install?url=" + (u.ipa.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? u.ipa)) }
    static var sideStoreSourceURL: URL? { URL(string: "sidestore://source?url=" + (altSource.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? altSource)) }
}
