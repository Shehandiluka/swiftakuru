import SwiftUI
import PhotosUI

@main
struct SwiftAkuruApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Setup", systemImage: "keyboard") }
            GuideView().tabItem { Label("Singlish", systemImage: "character.book.closed") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
            ThemesView().tabItem { Label("Themes", systemImage: "paintpalette") }
            MoreView().tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(Color(red: 0.23, green: 0.42, blue: 1))
    }
}

// MARK: - Setup
struct HomeView: View {
    @State private var test = ""
    @State private var update: AppUpdate? = UpdateChecker.cached()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let u = update { UpdateCard(u: u) }
                    HStack(spacing: 14) {
                        Image("Logo").resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading) {
                            Text("Swift Akuru").font(.largeTitle.bold())
                            Text("සිංහල + English keyboard · AI සමඟ").foregroundStyle(.secondary)
                        }
                    }
                    StepCard(n: 1, title: "Keyboard එක ON කරන්න", text: "පහළ button එක ඔබලා Settings → Keyboards → Swift Akuru ON කරන්න.")
                    StepCard(n: 2, title: "Allow Full Access ON කරන්න", text: "Clipboard, AI, sound/vibration වලට මේක ඕන. ඔයා type කරන දේවල් අපි save කරන්නේවත් යවන්නේවත් නැහැ (AI එකට යවන්නේ ඔයා ✨ ඔබපු text එක විතරයි).")
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        Label("Settings open කරන්න", systemImage: "gear").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent)
                    StepCard(n: 3, title: "🌐 globe එක ඔබලා Swift Akuru තෝරන්න", text: "ඕනෑම app එකක keyboard එකේ 🌐 key එක ඔබාගෙන ඉඳලා Swift Akuru තෝරන්න.")
                    Text("Test කරන්න").font(.headline)
                    TextField("මෙතන type කරලා බලන්න… (amma → අම්ම)", text: $test, axis: .vertical)
                        .lineLimit(3...6).padding(12).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
                    FeatureList()
                }.padding()
            }
            .navigationTitle("").navigationBarHidden(true)
            .task { update = await UpdateChecker.check(force: true) }
            .refreshable { update = await UpdateChecker.check(force: true) }
        }
    }
}

/// "New version" card – updates are installed with SideStore / AltStore (on the phone) or Sideloadly (PC).
struct UpdateCard: View {
    let u: AppUpdate
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Update එකක් තියෙනවා — v\(u.version) (build \(u.build))", systemImage: "arrow.down.circle.fill").font(.headline).foregroundStyle(.orange)
            ForEach(Array((u.notes ?? []).prefix(6).enumerated()), id: \.offset) { _, n in Text("• " + n).font(.subheadline) }
            Text("ඔයා දැන් පාවිච්චි කරන්නේ v\(UpdateChecker.currentVersion) (build \(UpdateChecker.currentBuild))").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { if let x = UpdateChecker.sideStoreURL(u) { openURL(x) } } label: { Label("SideStore", systemImage: "arrow.down.app") }.buttonStyle(.borderedProminent)
                Button { if let x = UpdateChecker.altStoreURL(u) { openURL(x) } } label: { Text("AltStore") }.buttonStyle(.bordered)
                Button { if let x = URL(string: u.ipa) { openURL(x) } } label: { Text(".ipa") }.buttonStyle(.bordered)
            }
            Text("SideStore / AltStore තියෙනවා නම් එක tap එකෙන් update වෙනවා. Sideloadly නම් .ipa එක download කරලා PC එකෙන් ආයේ දාන්න — settings, ඉගෙනගත් වචන නැති වෙන්නේ නැහැ.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.5)))
    }
}

struct StepCard: View {
    let n: Int; let title: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundStyle(.white).frame(width: 30, height: 30).background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(text).font(.subheadline).foregroundStyle(.secondary) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct FeatureList: View {
    let items = [
        ("character.cursor.ibeam", "Singlish → සිංහල live, smart suggestions, ඔයාගේ වචන ඉගෙනගන්නවා"),
        ("sparkles", "Swift AI: translate (සිංහල/English/தமிழ்), grammar fix, formal/friendly, reply ideas, Ask AI"),
        ("doc.on.clipboard", "Clipboard manager — copy කරපු දේවල් 40ක් දක්වා, pin කරන්න පුළුවන්"),
        ("face.smiling", "Emoji panel + වචනවලට ගැලපෙන emoji suggestions (adarei → ❤️)"),
        ("hand.draw", "Space bar එක ඇදලා cursor එක move කරන්න · long-press alternates"),
        ("paintpalette", "Themes 9ක් + ඔයාගේම photo එක background එකට"),
        ("text.badge.plus", "Text shortcuts (gm → Good morning! ☀️)"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Features").font(.headline)
            ForEach(items.indices, id: \.self) { k in let i = items[k];
                HStack(alignment: .top, spacing: 10) { Image(systemName: i.0).frame(width: 24).foregroundStyle(Color.accentColor); Text(i.1).font(.subheadline) }
            }
        }
    }
}

// MARK: - Singlish guide
struct GuideView: View {
    let rows: [(String, String)] = [
        ("amma", "අම්ම"), ("ammaa", "අම්මා"), ("thaaththaa", "තාත්තා"), ("kohomadha", "කොහොමද"), ("hozdhayi", "හොඳයි"), ("sthuthiyi", "ස්තුතියි"),
        ("laxkaava", "ලංකාව"), ("shrii", "ශ්‍රී"), ("prashnaya", "ප්‍රශ්නය"), ("vidhyaava", "විද්‍යාව"), ("kaeema", "කෑම"), ("aayuboovan", "ආයුබෝවන්"),
    ]
    let letters: [(String, String)] = [
        ("t / th", "ට / ත"), ("d / dh", "ඩ / ද"), ("T / Th", "ඨ / ථ"), ("D / Dh", "ඪ / ධ"), ("n / N", "න / ණ"), ("l / L", "ල / ළ"), ("s / sh / Sh", "ස / ශ / ෂ"),
        ("x", "ං"), ("zg / zd / zdh / zb", "ඟ / ඬ / ඳ / ඹ"), ("kn / gn", "ඤ / ඥ"), ("a / aa", "අ / ආ"), ("ae / aee", "ඇ / ඈ"), ("i / ii", "ඉ / ඊ (කී = kii)"),
        ("u / uu", "උ / ඌ"), ("e / ee", "එ / ඒ (කේ = kee)"), ("o / O", "ඔ / ඕ"), ("ai / au", "ඓ / ඖ"), ("Ru", "ඍ (කෘ)"), ("kr+vowel / ky+vowel", "ක්‍ර / ක්‍ය"),
    ]
    var body: some View {
        NavigationStack {
            List {
                Section("උදාහරණ") { ForEach(rows.indices, id: \.self) { k in let r = rows[k]; HStack { Text(r.0).font(.body.monospaced()); Spacer(); Text(r.1).font(.title3) } } }
                Section("අකුරු") { ForEach(letters.indices, id: \.self) { k in let r = letters[k]; HStack { Text(r.0).font(.body.monospaced()); Spacer(); Text(r.1).font(.title3) } } }
                Section("Tips") {
                    Text("• Key එකක් ඔබාගෙන ඉන්නකොට (long-press) ඒ අකුරේ අනිත් සිංහල අකුරු එනවා (n → ණ ං ඤ ඞ ඳ)")
                    Text("• Suggestion bar එකේ වෙනත් spelling (ත/ට, ද/ඩ…) පෙන්නනවා — tap කරන්න")
                    Text("• ‘අ’ key එකෙන් සියලුම සිංහල අකුරු සහ පිලි කෙලින්ම type කරන්න පුළුවන්")
                    Text("• EN / සිං key එකෙන් English ↔ Singlish මාරු කරන්න")
                }
            }.navigationTitle("Singlish guide")
        }
    }
}

// MARK: - AI
struct AISettingsView: View {
    @AppStorage(SharedStore.K.aiProvider, store: SharedStore.shared.defaults) var provider = "gemini"
    @AppStorage(SharedStore.K.aiKeyGemini, store: SharedStore.shared.defaults) var gemini = ""
    @AppStorage(SharedStore.K.aiKeyOpenAI, store: SharedStore.shared.defaults) var openai = ""
    @AppStorage(SharedStore.K.aiModelGemini, store: SharedStore.shared.defaults) var gModel = "gemini-2.5-flash"
    @AppStorage(SharedStore.K.aiModelOpenAI, store: SharedStore.shared.defaults) var oModel = "gpt-4.1-mini"
    @State private var testOut = ""
    @State private var testing = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $provider) { Text("Google Gemini (free)").tag("gemini"); Text("OpenAI").tag("openai") }
                    if provider == "gemini" {
                        SecureField("Gemini API key", text: $gemini)
                        TextField("Model", text: $gModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Link("Free key එකක් ගන්න → aistudio.google.com", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    } else {
                        SecureField("OpenAI API key (sk-…)", text: $openai)
                        TextField("Model", text: $oModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text(SharedStore.shared.hasAppGroup ? "Key එක keyboard එකටත් share වෙනවා." : "මේ install එකේ app ↔ keyboard share වෙන්නේ නැහැ (free Apple ID). Key එක copy කරලා keyboard එකේ ✨ AI → ‘Paste API key’ ඔබන්න.")
                }
                Section {
                    Button(testing ? "Testing…" : "AI test කරන්න") {
                        testing = true; testOut = ""
                        Task {
                            do { testOut = try await AIClient.run(.toSinhala, text: "Good morning! How are you today?") } catch { testOut = error.localizedDescription }
                            testing = false
                        }
                    }.disabled(testing)
                    if !testOut.isEmpty { Text(testOut) }
                    if !(provider == "gemini" ? gemini : openai).isEmpty {
                        Button("Key එක copy කරන්න (keyboard එකට paste කරන්න)") { UIPasteboard.general.string = provider == "gemini" ? gemini : openai }
                    }
                }
                Section("AI actions keyboard එකේ") {
                    Text("🇬🇧 English · 🇱🇰 සිංහල · தமிழ் translate · ✓ Grammar fix · 👔 Formal · 😊 Friendly · ✂️ Shorter · 💬 Reply ideas · ✨ Ask AI · 🎉 + Emoji").font(.subheadline)
                }
            }.navigationTitle("Swift AI")
        }
    }
}

// MARK: - Themes
struct ThemesView: View {
    @AppStorage(SharedStore.K.theme, store: SharedStore.shared.defaults) var themeId = "swift"
    @State private var photo: PhotosPickerItem?
    @State private var saved = false
    let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(KBTheme.all, id: \.id) { t in
                        Button { themeId = t.id } label: { ThemeSwatch(t: t, selected: themeId == t.id) }.buttonStyle(.plain)
                    }
                }.padding()
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photo, matching: .images) { Label("මගේ photo එක background එකට", systemImage: "photo") }
                        .buttonStyle(.borderedProminent)
                    if saved { Text("Saved ✓ — ‘My photo’ theme එක තෝරන්න").foregroundStyle(.green) }
                    if !SharedStore.shared.hasAppGroup { Text("Note: free Apple ID install එකේ photo theme එක keyboard එකට යන්නේ නැහැ (App Group ඕන). Keyboard එකේ ⚙️ වලින් අනිත් themes තෝරන්න පුළුවන්.").font(.footnote).foregroundStyle(.secondary) }
                }.padding(.horizontal)
            }
            .navigationTitle("Themes")
            .onChange(of: photo) { item in
                Task {
                    guard let item = item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                    let w: CGFloat = 900
                    let size = CGSize(width: w, height: img.size.height * w / max(img.size.width, 1))
                    let r = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                    try? r.jpegData(compressionQuality: 0.8)?.write(to: SharedStore.shared.customBackgroundURL)
                    themeId = "photo"; saved = true
                }
            }
        }
    }
}

struct ThemeSwatch: View {
    let t: KBTheme; let selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3) { _ in
                HStack(spacing: 4) { ForEach(0..<6) { _ in RoundedRectangle(cornerRadius: 3).fill(Color(t.key)).frame(height: 16) } }
            }
            Text(t.name).font(.caption.bold()).foregroundStyle(Color(t.keyText))
        }
        .padding(10)
        .background(LinearGradient(colors: (t.gradient ?? [t.background, t.background]).map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
    }
}

// MARK: - More: shortcuts, learned words, about
struct MoreView: View {
    @State private var shortcuts: [(String, String)] = SharedStore.shared.shortcuts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    @State private var newKey = ""
    @State private var newText = ""
    @State private var words: [(String, Int)] = Array(WordStore.shared.learnedList.prefix(300))
    @State private var checking = false
    @State private var checkMsg = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shortcuts.indices, id: \.self) { k in let s = shortcuts[k]; VStack(alignment: .leading) { Text(s.0).font(.body.monospaced().bold()); Text(s.1).foregroundStyle(.secondary) } }
                        .onDelete { idx in shortcuts.remove(atOffsets: idx); save() }
                    HStack {
                        TextField("gm", text: $newKey).frame(width: 70).autocorrectionDisabled().textInputAutocapitalization(.never)
                        TextField("Good morning! ☀️", text: $newText)
                        Button("Add") { guard !newKey.isEmpty, !newText.isEmpty else { return }; shortcuts.append((newKey, newText)); newKey = ""; newText = ""; save() }
                    }
                } header: { Text("Text shortcuts") } footer: { Text("Shortcut එක type කරලා space ඔබන්න.") }
                Section("ඉගෙනගත් වචන (\(words.count))") {
                    ForEach(words.indices, id: \.self) { k in let w = words[k]; HStack { Text(w.0); Spacer(); Text("\(w.1)").foregroundStyle(.secondary) } }
                        .onDelete { idx in for i in idx { WordStore.shared.forget(words[i].0) }; words.remove(atOffsets: idx) }
                }
                Section("Updates") {
                    HStack { Text("Version"); Spacer(); Text("\(UpdateChecker.currentVersion) (build \(UpdateChecker.currentBuild))").foregroundStyle(.secondary) }
                    Button(checking ? "Checking…" : "Update තියෙනවද බලන්න") {
                        checking = true
                        Task { let u = await UpdateChecker.check(force: true); checkMsg = u.map { "v\($0.version) (build \($0.build)) තියෙනවා — Setup tab එකේ Update ඔබන්න" } ?? "ඔයා ළඟ තියෙන්නේ අලුත්ම version එක ✓"; checking = false }
                    }.disabled(checking)
                    if !checkMsg.isEmpty { Text(checkMsg).font(.footnote) }
                    Button("Auto-update: SideStore එකට Swift Akuru source එක add කරන්න") { if let x = UpdateChecker.sideStoreSourceURL { UIApplication.shared.open(x) } }
                }
                Section("About") {
                    Text("Swift Akuru \(UpdateChecker.currentVersion) — SwiftPayPOS (Private) Limited")
                    Link("swiftlk.com", destination: URL(string: "https://swiftlk.com")!)
                    Text("Privacy: ඔයා type කරන දේ phone එකේම තියෙනවා. Internet එකට යන්නේ ඔයා AI button එක ඔබපු text එක විතරයි (Google/OpenAI වෙත).").font(.footnote)
                }
            }.navigationTitle("More")
        }
    }
    private func save() { SharedStore.shared.shortcuts = Dictionary(shortcuts, uniquingKeysWith: { _, b in b }) }
}
