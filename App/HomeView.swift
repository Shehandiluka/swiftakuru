import SwiftUI

/// Home: a clean dashboard. Setup steps appear only while the keyboard still needs them.
struct HomeView: View {
    @ObservedObject private var acc = AppAccount.shared
    @Environment(\.scenePhase) private var phase
    @State private var update: AppUpdate? = UpdateChecker.cached()
    @State private var kbOn = AppAccount.keyboardEnabled
    @State private var fullAccess = AppAccount.fullAccess
    @State private var test = ""
    @State private var showSetupAnyway = false
    @State private var stats = WordStore.shared.stats

    private var ready: Bool { kbOn && fullAccess != false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    if let s = Season.current() { seasonBanner(s) }
                    if let u = update { UpdateCard(u: u) }
                    if !ready || showSetupAnyway { setupCard }
                    quickActions
                    tryItCard
                    statsRow
                    if !UpdateChecker.installedWithSideStore && update == nil {
                        NavigationLink { NoLaptopGuide() } label: {
                            row(icon: "iphone.and.arrow.forward", title: "Laptop නැතුව updates", sub: "SideStore එකට මාරු වෙන්න — එක පාරයි")
                        }.buttonStyle(.plain)
                    }
                    HStack {
                        Spacer()
                        Text("Swift Akuru v\(UpdateChecker.currentVersion) · SwiftPayPOS (Pvt) Ltd").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .task { await refreshAll() }
            .refreshable { await refreshAll() }
            .onChange(of: phase) { p in if p == .active { Task { await refreshAll() } } }
        }
    }

    private func refreshAll() async {
        kbOn = AppAccount.keyboardEnabled
        fullAccess = AppAccount.fullAccess
        WordStore.shared.waitUntilLoaded()
        stats = WordStore.shared.stats
        await acc.ping()
        await acc.refresh()
        update = await UpdateChecker.check(force: true)
    }

    // MARK: hero
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let g = h < 12 ? "සුභ උදෑසනක්" : (h < 17 ? "සුභ දහවලක්" : "සුභ සන්ධ්‍යාවක්")
        if let n = acc.firstName { return "\(g), \(n)" }
        return g
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image("Logo").resizable().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                Spacer()
                NavigationLink { AccountView() } label: {
                    if let p = acc.profile, acc.signedIn {
                        Avatar(url: p.picture, name: p.name ?? "?", size: 40).overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))
                    } else {
                        Text("Sign in").font(.subheadline.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(.white.opacity(0.18)).clipShape(Capsule())
                    }
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                Text("Swift Akuru").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("සිංහල · English · AI keyboard").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 8) {
                chip(kbOn ? "Keyboard ON" : "Keyboard OFF", ok: kbOn)
                chip(fullAccess == nil ? "Full Access ?" : (fullAccess! ? "Full Access" : "Full Access OFF"), ok: fullAccess ?? true)
                if acc.isPremium { chip("★ Premium", ok: true) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                heroGradient
                Circle().fill(.white.opacity(0.10)).frame(width: 220).offset(x: 150, y: -90)
                Circle().fill(.white.opacity(0.06)).frame(width: 160).offset(x: -140, y: 90)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 8)
        .onLongPressGesture { showSetupAnyway.toggle() }
    }

    private func chip(_ t: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(t).font(.caption.weight(.semibold)).foregroundStyle(.white)
        }.padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.22)).clipShape(Capsule())
    }

    private func seasonBanner(_ s: Season) -> some View {
        HStack(spacing: 12) {
            Text(Season.icons[s.id] ?? "🎉").font(.system(size: 30))
            Text(s.greeting).font(.subheadline.weight(.semibold))
            Spacer()
        }.padding(14).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: setup (only while needed)
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kbOn ? "එක පියවරක් තව" : "Keyboard එක සකස් කරමු").font(.headline)
            step(1, "Settings → General → Keyboard → Keyboards → Add → Swift Akuru", done: kbOn)
            step(2, "Swift Akuru ඔබලා Allow Full Access ON කරන්න (AI, clipboard, sound වලට)", done: fullAccess == true)
            step(3, "ඕනම app එකක 🌐 ඔබාගෙන ඉඳලා Swift Akuru තෝරන්න", done: kbOn && fullAccess == true)
            Button {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            } label: {
                Text("Settings open කරන්න").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(heroGradient).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
            Text("ඔයා type කරන දේවල් අපි save කරන්නේවත් යවන්නේවත් නැහැ.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func step(_ n: Int, _ t: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.green : Color.white.opacity(0.12)).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.caption.bold()) } else { Text("\(n)").font(.caption.bold()) }
            }
            Text(t).font(.subheadline).foregroundStyle(done ? .secondary : .primary).strikethrough(done)
        }
    }

    // MARK: quick actions
    private var quickActions: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            tile("character.bubble.fill", "Translate & Reply", "ඕනම භාෂාවක්", [.purple, .blue]) { TranslateView(input: .none).navigationTitle("🌐 Translate & Reply") }
            tile("sparkles", "Swift AI", "ලියන්න, හදන්න", [.pink, .purple]) { AISettingsView() }
            tile("paintpalette.fill", "Themes", "Keyboard පෙනුම", [.orange, .pink]) { ThemesView() }
            tile("brain.head.profile", "ඉගැන්නන්න", "\(stats.words) වචන දන්නවා", [.teal, .blue]) { MoreView() }
            tile("character.book.closed.fill", "Singlish guide", "amma → අම්ම", [.green, .teal]) { GuideView() }
            tile("person.crop.circle.fill", acc.signedIn ? "Account" : "Sign in", acc.signedIn ? (acc.profile?.email ?? "") : "Google", [.indigo, .purple]) { AccountView() }
        }
    }

    private func tile<D: View>(_ icon: String, _ title: String, _ sub: String, _ colors: [Color], @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var tryItCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type කරලා බලන්න").font(.headline)
            TextField("amma → අම්ම · kohomada → කොහොමද", text: $test, axis: .vertical)
                .lineLimit(2...5).padding(12).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("\(stats.words)", "වචන ඉගෙනගෙන")
            stat("\(stats.pairs)", "වාක්‍ය රටා")
            stat("\(stats.spellings)", "ඔයාගේ spellings")
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold()).monospacedDigit()
            Text(l).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func row(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 32)
            VStack(alignment: .leading) { Text(title).font(.subheadline.bold()); Text(sub).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(14).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
