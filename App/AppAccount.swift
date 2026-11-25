import SwiftUI
import AuthenticationServices
import UIKit

/// Swift Akuru account (Google sign-in) + anonymous app stats for the owner's dashboard.
/// Stats = app version, iOS version, device model, language, keyboard on/off. Never anything typed.
@MainActor
final class AppAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AppAccount()
    static let base = URL(string: "https://swiftakuru-chat.shehandsandeep.workers.dev")!

    struct Profile: Codable, Equatable { let id: String; let email: String?; let name: String?; let picture: String?; let plan: String }
    @Published private(set) var profile: Profile?
    @Published var busy = false
    @Published var message: String?
    @AppStorage("shareStats", store: SharedStore.shared.defaults) var shareStats = true

    private var token: String? {
        // Keychain first; if this install can't use the Keychain (some sideload tools), fall back to app settings
        get { SecureStore.string("app.session") ?? UserDefaults.standard.string(forKey: "app.session.fb") }
        set {
            if let v = newValue {
                SecureStore.setString(v, for: "app.session")
                if SecureStore.string("app.session") == nil { UserDefaults.standard.set(v, forKey: "app.session.fb") }
            } else { SecureStore.delete("app.session"); UserDefaults.standard.removeObject(forKey: "app.session.fb") }
            objectWillChange.send()
        }
    }
    var signedIn: Bool { token != nil }
    var firstName: String? { profile?.name?.split(separator: " ").first.map(String.init) }
    var isPremium: Bool { profile?.plan == "premium" }

    /// Random id for this install (no personal data); kept in the Keychain so a reinstall counts once.
    static var installId: String {
        if let v = SecureStore.string("app.installId") ?? SharedStore.shared.defaults.string(forKey: "installId") { return v }
        let v = UUID().uuidString
        SecureStore.setString(v, for: "app.installId"); SharedStore.shared.defaults.set(v, forKey: "installId")
        return v
    }

    static var keyboardEnabled: Bool {
        let me = (Bundle.main.bundleIdentifier ?? "store.swiftpaypos.swiftakuru").lowercased()
        return UITextInputMode.activeInputModes.contains { (($0.value(forKey: "identifier") as? String) ?? "").lowercased().hasPrefix(me) }
    }
    /// Written by the keyboard (only visible when app and keyboard share the App Group).
    static var fullAccess: Bool? { SharedStore.shared.defaults.object(forKey: "kb.fullAccess") as? Bool }

    override init() {
        super.init()
        if let d = SharedStore.shared.defaults.data(forKey: "app.profile"), let p = try? JSONDecoder().decode(Profile.self, from: d) { profile = p }
    }

    // MARK: stats
    func ping() async {
        guard shareStats else { return }
        var sys = utsname(); uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        let body: [String: Any?] = [
            "installId": Self.installId, "version": UpdateChecker.currentVersion, "build": UpdateChecker.currentBuild,
            "ios": UIDevice.current.systemVersion, "model": model, "locale": Locale.preferredLanguages.first ?? "",
            "source": UpdateChecker.installedWithSideStore ? "SideStore" : "other",
            "keyboardOn": Self.keyboardEnabled, "fullAccess": Self.fullAccess,
        ]
        _ = try? await request("/v1/app/ping", method: "POST", body: body.compactMapValues { $0 })
    }

    // MARK: Google sign-in
    func signInWithGoogle() {
        guard !busy else { return }
        busy = true; message = nil
        var c = URLComponents(url: Self.base.appendingPathComponent("auth/google/start"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "install", value: Self.installId)]
        let session = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "swiftakuru") { [weak self] url, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.busy = false
                if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return }
                guard let url = url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { self.message = "Sign-in අසාර්ථකයි."; return }
                if let err = items.first(where: { $0.name == "error" })?.value {
                    self.message = err == "google_not_configured" ? "Google sign-in තාම සකස් කරලා නැහැ (server එකේ Google keys දාන්න ඕන)." : "Sign-in අසාර්ථකයි (\(err))."
                    return
                }
                guard let t = items.first(where: { $0.name == "token" })?.value else { return }
                self.token = t
                await self.refresh()
                await self.ping()
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        if !session.start() { busy = false; message = "Sign-in window එක open කරන්න බැරි වුණා." }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    func refresh() async {
        guard signedIn else { return }
        do {
            let d = try await request("/v1/app/me", method: "GET", body: nil)
            struct R: Decodable { let account: Profile }
            let p = try JSONDecoder().decode(R.self, from: d).account
            profile = p
            SharedStore.shared.defaults.set(try? JSONEncoder().encode(p), forKey: "app.profile")
        } catch let e as APIError where e.status == 401 { signOutLocally() } catch {}
    }

    func signOut() async {
        _ = try? await request("/v1/app/logout", method: "POST", body: [:])
        signOutLocally()
    }
    func deleteAccount() async {
        do { _ = try await request("/v1/app/account", method: "DELETE", body: nil); signOutLocally(); message = "Account එක මකලා දැම්මා." }
        catch { message = "මකන්න බැරි වුණා — පස්සේ ආයේ උත්සාහ කරන්න." }
    }
    private func signOutLocally() {
        token = nil; profile = nil
        SharedStore.shared.defaults.removeObject(forKey: "app.profile")
    }

    struct APIError: Error { let status: Int }
    private func request(_ path: String, method: String, body: [String: Any]?) async throws -> Data {
        var r = URLRequest(url: Self.base.appendingPathComponent(String(path.dropFirst())))
        r.httpMethod = method
        r.timeoutInterval = 20
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let b = body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject: b) }
        let (d, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError(status: code) }
        return d
    }
}

// MARK: - Account screen
struct AccountView: View {
    @ObservedObject var acc = AppAccount.shared
    @State private var confirmDelete = false
    var body: some View {
        List {
            if let p = acc.profile, acc.signedIn {
                Section {
                    HStack(spacing: 14) {
                        WebAvatar(url: p.picture, name: p.name ?? "?", size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name ?? "").font(.title3.bold())
                            Text(p.email ?? "").font(.subheadline).foregroundStyle(.secondary)
                            Text(p.plan == "premium" ? "★ Premium" : "Free").font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(p.plan == "premium" ? AnyShapeStyle(heroGradient) : AnyShapeStyle(Color.gray.opacity(0.25))))
                        }
                    }.padding(.vertical, 6)
                }
                Section {
                    Button("Sign out") { Task { await acc.signOut() } }
                    Button("Account එක මකන්න", role: .destructive) { confirmDelete = true }
                }
            } else {
                Section {
                    VStack(spacing: 14) {
                        Image("Logo").resizable().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 18))
                        Text("Swift Akuru account").font(.title2.bold())
                        Text("Google account එකෙන් sign in වෙන්න. ඔයාගේ නම, email සහ photo විතරයි ගන්නේ.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button { acc.signInWithGoogle() } label: {
                            HStack(spacing: 10) {
                                Text("G").font(.system(size: 20, weight: .bold)).foregroundStyle(
                                    LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Text(acc.busy ? "Opening…" : "Continue with Google").font(.headline).foregroundStyle(.black)
                            }.frame(maxWidth: .infinity).padding(.vertical, 13).background(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).disabled(acc.busy)
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
            if let m = acc.message { Section { Text(m).font(.subheadline).foregroundStyle(.orange) } }
            Section {
                Toggle("App usage stats යවන්න (නම නැතුව)", isOn: $acc.shareStats)
            } footer: {
                Text("යවන්නේ: app version, iOS version, phone model, භාෂාව, keyboard ON ද කියන එක විතරයි. ඔයා type කරන කිසිම දෙයක් කවදාවත් යවන්නේ නැහැ.")
            }
        }
        .navigationTitle("Account")
        .task { await acc.refresh() }
        .confirmationDialog("Account එක සහ ඒකේ data සම්පූර්ණයෙන්ම මකන්නද?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("මකන්න", role: .destructive) { Task { await acc.deleteAccount() } }
        }
    }
}

struct WebAvatar: View {
    let url: String?; let name: String; let size: CGFloat
    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { initials }
            } else { initials }
        }.frame(width: size, height: size).clipShape(Circle())
    }
    private var initials: some View {
        ZStack { Circle().fill(heroGradient); Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white) }
    }
}

let heroGradient = LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.98), Color(red: 0.23, green: 0.51, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
