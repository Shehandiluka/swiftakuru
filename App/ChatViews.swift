import SwiftUI
import LocalAuthentication

// MARK: - Chat tab root
struct ChatRootView: View {
    @StateObject private var chat = ChatService.shared
    var body: some View {
        NavigationStack {
            Group {
                if !ChatCrypto.isSupported {
                    ContentUnavailableCompat(title: "iOS 17 ඕන", text: "Swift Akuru Chat end-to-end encryption එකට iOS 17 හෝ ඊට අලුත් version එකක් ඕන.")
                } else if !chat.isSignedIn {
                    RegisterView()
                } else {
                    ChatHomeView()
                }
            }
        }
        .environmentObject(chat)
    }
}

struct ContentUnavailableCompat: View {
    let title: String; let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding()
    }
}

// MARK: - Registration (phone + OTP)
struct RegisterView: View {
    @EnvironmentObject var chat: ChatService
    @AppStorage("chatCallingCode", store: SharedStore.shared.defaults) private var callingCode = "94"
    @State private var name = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var discoverable = true
    @State private var sentTo: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Swift Akuru Chat — Swift Akuru තියෙන අය එක්ක chat කරන්න. පණිවිඩ end-to-end encrypt වෙනවා; server එකට ඒවා කියවන්න බැහැ.").font(.subheadline)
            }
            if sentTo == nil {
                Section("ඔයාගේ විස්තර") {
                    TextField("නම (අනිත් අයට පේන්න)", text: $name)
                    HStack {
                        Text("+")
                        TextField("94", text: $callingCode).keyboardType(.numberPad).frame(width: 50)
                        TextField("Phone number (0771234567)", text: $phone).keyboardType(.phonePad)
                    }
                    Toggle("Phone number එකෙන් මාව හොයාගන්න දෙන්න", isOn: $discoverable)
                }
                Button(busy ? "යවනවා…" : "Code එක එවන්න") { Task { await sendCode() } }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || phone.count < 7)
            } else {
                Section("SMS code එක (\(PhoneNumber.display(sentTo ?? "")))") {
                    TextField("123456", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button(busy ? "බලනවා…" : "Verify") { Task { await verify() } }.disabled(busy || code.count != 6)
                    Button("Number එක වෙනස් කරන්න") { sentTo = nil; code = "" }
                }
            }
            if let e = error { Section { Text(e).foregroundStyle(.red).font(.footnote) } }
            Section {
                Text("දැනට SMS යවන්න test numbers විතරයි (SMS provider එකක් තවම set කරලා නැහැ). ඔයාගේ phone number එක server එකේ තියෙන්නේ hash එකක් විදියට විතරයි; කාටවත් පේන්නේ නැහැ.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Chat")
    }

    private func sendCode() async {
        error = nil
        guard let p = PhoneNumber.normalize(phone, defaultCallingCode: callingCode) else { error = "Phone number එක හරි නැහැ"; return }
        busy = true; defer { busy = false }
        do { try await chat.requestCode(phone: p); sentTo = p } catch { self.error = describe(error) }
    }
    private func verify() async {
        guard let p = sentTo else { return }
        busy = true; defer { busy = false }
        do { try await chat.verify(phone: p, code: code, name: name.trimmingCharacters(in: .whitespaces), discoverable: discoverable) }
        catch { self.error = describe(error) }
    }
}

func describe(_ e: Error) -> String {
    guard let a = e as? ChatAPI.APIError else { return "Internet connection එක බලන්න" }
    switch a.code {
    case "rate_limited": return "ගොඩක් උත්සාහ කළා — ටිකකින් ආයේ try කරන්න"
    case "wrong_code": return "Code එක හරි නැහැ"
    case "code_expired": return "Code එක expire වෙලා — අලුත් එකක් ඉල්ලන්න"
    case "sms_not_configured": return "මේ number එකට SMS යවන්න තවම බැහැ (test numbers විතරයි)"
    case "bad_phone": return "Phone number එක හරි නැහැ"
    case "invite_pending": return "Invitation එකක් දැනටමත් යවලා තියෙනවා"
    case "already_secret": return "මේක දැනටමත් Secret Chat එකක්"
    case "not_found": return "හම්බ වුණේ නැහැ"
    default: return "Error: \(a.code)"
    }
}

// MARK: - Conversation list
struct ChatHomeView: View {
    @EnvironmentObject var chat: ChatService
    @State private var showNew = false
    @State private var showSecret = false
    @State private var addToSecret: ChatConversation?
    @State private var reportTarget: ChatConversation?
    @State private var open: String?

    var normal: [ChatConversation] { _ = chat.revision; return chat.db.conversations().filter { !$0.secret && !$0.hidden } }
    var invitations: [ChatInvitation] { _ = chat.revision; return chat.db.invitations() }

    var body: some View {
        List {
            if !invitations.isEmpty {
                Section("Secret Chat invitations") {
                    ForEach(invitations) { inv in InvitationRow(inv: inv) }
                }
            }
            Section {
                Button { showSecret = true } label: { Label("Secret Chats", systemImage: "lock.fill") }
            }
            Section("Chats") {
                if normal.isEmpty { Text("තවම chats නැහැ. + ඔබලා phone number එකෙන් හොයන්න.").foregroundStyle(.secondary) }
                ForEach(normal) { c in
                    NavigationLink(value: c.id) { ConversationRow(c: c) }
                        .contextMenu {
                            Button { open = c.id } label: { Label("Open Chat", systemImage: "bubble.left") }
                            Button { addToSecret = c } label: { Label("Add to Secret Chat", systemImage: "lock") }
                            Button { reportTarget = c } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                            Button(role: .destructive) { Task { await chat.block(c) } } label: { Label("Block User", systemImage: "hand.raised") }
                            Button(role: .destructive) { Task { await chat.deleteConversation(c.id) } } label: { Label("Delete Conversation", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("Chat")
        .navigationDestination(for: String.self) { ChatThreadView(conversationId: $0) }
        .navigationDestination(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) { if let o = open { ChatThreadView(conversationId: o) } }
        .navigationDestination(isPresented: $showSecret) { SecretGateView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } }
            ToolbarItem(placement: .topBarLeading) { NavigationLink { ChatSettingsView() } label: { Image(systemName: "gearshape") } }
        }
        .sheet(isPresented: $showNew) { NewChatView { cid in showNew = false; open = cid } }
        .sheet(item: $addToSecret) { c in AddToSecretSheet(c: c) }
        .sheet(item: $reportTarget) { c in ReportSheet(c: c) }
        .refreshable { await chat.refreshConversations(); await chat.sync() }
        .task { await chat.refreshConversations(); chat.startPolling(every: 5) }
        .onDisappear { chat.stopPolling() }
    }
}

struct ConversationRow: View {
    @EnvironmentObject var chat: ChatService
    let c: ChatConversation
    var body: some View {
        let last = chat.db.lastMessage(conversationId: c.id)
        let unread = chat.db.unreadCount(conversationId: c.id)
        HStack(spacing: 12) {
            Avatar(name: c.partnerName)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(c.partnerName).font(.headline)
                    if c.secret { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    if c.keyChanged { Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                }
                Text(last.map { ($0.outgoing ? "ඔයා: " : "") + $0.text } ?? "—").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let l = last { Text(shortTime(l.sentAt)).font(.caption2).foregroundStyle(.secondary) }
                if unread > 0 { Text("\(unread)").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.accentColor)) }
            }
        }
    }
}

struct Avatar: View {
    let name: String
    var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white)
            .frame(width: 40, height: 40).background(Circle().fill(Color.accentColor.gradient))
    }
}

func shortTime(_ t: Int) -> String {
    let d = Date(timeIntervalSince1970: TimeInterval(t))
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
    return f.string(from: d)
}

struct InvitationRow: View {
    @EnvironmentObject var chat: ChatService
    let inv: ChatInvitation
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if inv.incoming {
                Text("🔒 \(inv.fromName) ඔයාව Secret Chat එකකට invite කරනවා").font(.subheadline)
                HStack {
                    Button("Accept") { Task { do { try await chat.respond(inv, accept: true) } catch { self.error = describe(error) } } }.buttonStyle(.borderedProminent)
                    Button("Decline") { Task { do { try await chat.respond(inv, accept: false) } catch { self.error = describe(error) } } }.buttonStyle(.bordered)
                }
            } else {
                Text("⏳ Secret Chat invitation එක යැව්වා — අනිත් කෙනා accept කරනකම් ඉන්නවා").font(.subheadline).foregroundStyle(.secondary)
            }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }
}

// MARK: - New chat (search by phone)
struct NewChatView: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let onOpen: (String) -> Void
    @State private var phone = ""
    @State private var result: ChatAPI.User?
    @State private var normalized: String?
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Phone number එකෙන් හොයන්න") {
                    TextField("+94771234567", text: $phone).keyboardType(.phonePad)
                    Button(busy ? "හොයනවා…" : "Search") { Task { await search() } }.disabled(busy || phone.count < 7)
                }
                if let u = result {
                    Section {
                        HStack { Avatar(name: u.displayName); Text(u.displayName).font(.headline) }
                        Button("Start Chat") { Task { await start(u) } }.buttonStyle(.borderedProminent)
                    }
                }
                if let m = message { Section { Text(m).foregroundStyle(.secondary) } }
            }
            .navigationTitle("New chat")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func search() async {
        result = nil; message = nil
        guard let p = PhoneNumber.normalize(phone, defaultCallingCode: chat.defaultCallingCode) else { message = "Phone number එක හරි නැහැ"; return }
        busy = true; defer { busy = false }
        do {
            if let u = try await chat.lookup(phone: p) { result = u; normalized = p }
            else { message = "මේ number එකෙන් Swift Akuru user කෙනෙක් හම්බ වුණේ නැහැ" }
        } catch { message = describe(error) }
    }
    private func start(_ u: ChatAPI.User) async {
        do { let cid = try await chat.startConversation(with: u, phone: normalized); onOpen(cid) } catch { message = describe(error) }
    }
}

// MARK: - Thread
struct ChatThreadView: View {
    @EnvironmentObject var chat: ChatService
    let conversationId: String
    @State private var text = ""
    @State private var showSafety = false

    var conv: ChatConversation? { _ = chat.revision; return chat.db.conversation(conversationId) }
    var msgs: [ChatMessage] { _ = chat.revision; return chat.db.messages(conversationId: conversationId) }

    var body: some View {
        VStack(spacing: 0) {
            if let c = conv, c.keyChanged {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(c.partnerName) ගේ encryption key එක වෙනස් වෙලා (අලුත් phone / reinstall). Safety number එක check කරන්න.").font(.caption)
                    Button("Check") { showSafety = true }.font(.caption.bold())
                }.padding(8).background(Color.orange.opacity(0.15))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(msgs) { m in MessageBubble(m: m).id(m.id) }
                    }.padding(.horizontal).padding(.top, 8)
                }
                .onChange(of: msgs.count) { _ in if let l = msgs.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                .onAppear { if let l = msgs.last { proxy.scrollTo(l.id, anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                TextField("Message", text: $text, axis: .vertical).lineLimit(1...5)
                    .padding(10).background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                Button { let t = text; text = ""; Task { await chat.send(t, in: conversationId) } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || conv?.partnerDeleted == true)
            }.padding(8)
        }
        .navigationTitle((conv?.secret == true ? "🔒 " : "") + (conv?.partnerName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSafety = true } label: { Image(systemName: "checkmark.shield") } } }
        .sheet(isPresented: $showSafety) { if let c = conv { SafetyNumberView(c: c) } }
        .task { await chat.sync(); await chat.markRead(conversationId) }
        .onChange(of: chat.revision) { _ in Task { await chat.markRead(conversationId) } }
    }
}

struct MessageBubble: View {
    let m: ChatMessage
    var statusIcon: String {
        switch m.status { case .pending: return "clock"; case .failed: return "exclamationmark.circle"; case .sent: return "checkmark"; case .delivered, .read: return "checkmark.circle"; case .received: return "" }
    }
    var body: some View {
        HStack {
            if m.outgoing { Spacer(minLength: 40) }
            VStack(alignment: .trailing, spacing: 2) {
                Text(m.text).foregroundStyle(m.outgoing ? .white : .primary)
                HStack(spacing: 3) {
                    Text(shortTime(m.sentAt) == "" ? "" : timeOnly(m.sentAt)).font(.caption2)
                    if m.outgoing { Image(systemName: statusIcon).font(.caption2); if m.status == .read { Text("read").font(.caption2) } }
                }.foregroundStyle(m.outgoing ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(m.outgoing ? Color.accentColor : Color(.secondarySystemBackground)))
            if !m.outgoing { Spacer(minLength: 40) }
        }
    }
    func timeOnly(_ t: Int) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date(timeIntervalSince1970: TimeInterval(t))) }
}

struct SafetyNumberView: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let c: ChatConversation
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Safety number").font(.title2.bold())
                Text(ChatCrypto.safetyNumber(ChatIdentity.current().map(ChatIdentity.publicBase64) ?? "", c.partnerKey))
                    .font(.system(.title3, design: .monospaced)).multilineTextAlignment(.center)
                Text("\(c.partnerName) ගේ phone එකේ මේ chat එකේ තියෙන number එකත් මේකමද කියලා call එකකින් හරි මුණගැහිලා හරි බලන්න. එකම නම් ඔයාලා දෙන්නා අතරේ වෙන කෙනෙක් නැහැ.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if c.keyChanged {
                    Button("Numbers එකයි — අලුත් key එක trust කරන්න") { chat.trustNewKey(c.id); dismiss() }.buttonStyle(.borderedProminent)
                }
                Spacer()
            }.padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Add to Secret Chat
struct AddToSecretSheet: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let c: ChatConversation
    @State private var error: String?
    @State private var sent = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("🔒 \(c.partnerName) එක්ක chat එක Secret Chat එකක් කරන්නද?").font(.headline)
                }
                Section("මොකද වෙන්නේ") {
                    Text("• \(c.partnerName) ට invitation එකක් යනවා. එයා accept කළොත් විතරයි Secret Chat වෙන්නේ — දෙන්නාම එකඟ වෙන්න ඕන.")
                    Text("• Chat එක සාමාන්‍ය list එකෙන් අයින් වෙලා Secret Chats යටතට යනවා. Keyboard එකේ 🔒 එකෙන් ඔයාගේ PIN + එයාගේ phone number එක ගහලා විවෘත කරන්න පුළුවන්.")
                    Text("• පණිවිඩ කලින් වගේම end-to-end encrypted. List එකෙන් හංගන එක encryption එකක් නෙවෙයි — කාට හරි ඔයාගේ unlock කරපු phone එක ලැබුණොත්, screenshots, notifications වලින් තවමත් දැකගන්න පුළුවන්.")
                    Text("• Decline කළොත් chat එක කලින් වගේම තියෙනවා. Invitation එක දවස් 2කින් expire වෙනවා.")
                }.font(.subheadline)
                if !SecretPIN.shared.isSet {
                    Section { Text("ඔයාට තවම Secret Chat PIN එකක් නැහැ. Settings එකෙන් PIN එකක් set කරන්න — නැත්නම් keyboard එකෙන් විවෘත කරන්න බැහැ.").foregroundStyle(.orange) }
                }
                if let e = error { Section { Text(e).foregroundStyle(.red) } }
                Section {
                    Button(sent ? "Invitation එක යැව්වා ✓" : "Invitation එක යවන්න") {
                        Task { do { try await chat.inviteToSecret(c.id); sent = true } catch { self.error = describe(error) } }
                    }.disabled(sent)
                }
            }
            .navigationTitle("Add to Secret Chat")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct ReportSheet: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let c: ChatConversation
    @State private var reason = "spam"
    @State private var details = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("හේතුව", selection: $reason) {
                    Text("Spam").tag("spam"); Text("Harassment").tag("harassment"); Text("Scam").tag("scam"); Text("වෙනත්").tag("other")
                }
                TextField("විස්තර (optional)", text: $details, axis: .vertical)
                Text("Report එකට යන්නේ ඔයා ලියන හේතුව විතරයි. පණිවිඩ encrypted නිසා server එකට ඒවා කියවන්න බැහැ.").font(.footnote).foregroundStyle(.secondary)
                Button("Report \(c.partnerName)") { Task { await chat.reportUser(c, reason: reason + (details.isEmpty ? "" : ": " + details)); dismiss() } }
            }
            .navigationTitle("Report")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Secret Chats (PIN gate)
struct SecretGateView: View {
    @EnvironmentObject var chat: ChatService
    @AppStorage("secretFaceID", store: SharedStore.shared.defaults) private var useFaceID = false
    @State private var unlocked = false
    @State private var pin = ""
    @State private var message: String?

    var secrets: [ChatConversation] { _ = chat.revision; return chat.db.conversations().filter { $0.secret && !$0.hidden } }

    var body: some View {
        Group {
            if !SecretPIN.shared.isSet {
                SetPINView(onDone: { unlocked = true })
            } else if unlocked {
                List {
                    if secrets.isEmpty { Text("තවම Secret Chats නැහැ. Chat එකක් long-press කරලා \"Add to Secret Chat\" ඔබන්න.").foregroundStyle(.secondary) }
                    ForEach(secrets) { c in
                        NavigationLink { ChatThreadView(conversationId: c.id) } label: { ConversationRow(c: c) }
                            .swipeActions { Button("Leave") { Task { await chat.leaveSecret(c.id) } }.tint(.orange) }
                    }
                    Section { Button("🔒 Lock") { unlocked = false } }
                }
            } else {
                Form {
                    Section("Secret Chat PIN") {
                        SecureField("PIN", text: $pin).keyboardType(.numberPad)
                        Button("Unlock") { check() }
                        if useFaceID { Button("Face ID / Touch ID") { biometric() } }
                    }
                    if let m = message { Text(m).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("🔒 Secret Chats")
        .onDisappear { unlocked = false; pin = "" }
        .onAppear { if useFaceID && SecretPIN.shared.isSet && !unlocked { biometric() } }
    }

    private func check() {
        let p = pin; pin = ""
        switch SecretPIN.shared.verify(p) {
        case .ok: unlocked = true; message = nil
        case .wrong(let left): message = left > 0 ? "PIN එක හරි නැහැ (තව \(left) පාරයි)" : "PIN එක හරි නැහැ"
        case .locked(let until): message = "Lock වෙලා — \(Int(until.timeIntervalSinceNow / 60) + 1) min"
        case .notSet: break
        }
    }
    private func biometric() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Secret Chats විවෘත කරන්න") { ok, _ in
            DispatchQueue.main.async { if ok { unlocked = true } }
        }
    }
}

struct SetPINView: View {
    var onDone: () -> Void
    @State private var current = ""
    @State private var pin = ""
    @State private var confirm = ""
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Text("Secret Chat PIN එක ඔයාගේ phone එකේ විතරයි තියෙන්නේ. Server එකට යවන්නේ නැහැ; අනිත් කෙනාට ඔයාගේ PIN එක දැනගන්න ඕන නැහැ. ඉලක්කම් 4–8ක් (1234, 0000 වගේ ලේසි ඒවා බැහැ).").font(.footnote)
            }
            if SecretPIN.shared.isSet { SecureField("දැන් තියෙන PIN එක", text: $current).keyboardType(.numberPad) }
            SecureField("අලුත් PIN", text: $pin).keyboardType(.numberPad)
            SecureField("ආයේ ගහන්න", text: $confirm).keyboardType(.numberPad)
            Button("PIN එක save කරන්න") {
                guard pin == confirm else { message = "PIN දෙක ගැළපෙන්නේ නැහැ"; return }
                guard SecretPIN.isAcceptable(pin) else { message = "ඉලක්කම් 4–8ක්, ලේසියෙන් අනුමාන කරන්න බැරි එකක් දාන්න"; return }
                if SecretPIN.shared.set(pin, current: SecretPIN.shared.isSet ? current : nil) { pin = ""; confirm = ""; current = ""; onDone() }
                else { message = "දැන් තියෙන PIN එක හරි නැහැ" }
            }
            if let m = message { Text(m).foregroundStyle(.red) }
        }
        .navigationTitle("Secret Chat PIN")
    }
}

// MARK: - Settings & privacy
struct ChatSettingsView: View {
    @EnvironmentObject var chat: ChatService
    @AppStorage("chatCallingCode", store: SharedStore.shared.defaults) private var callingCode = "94"
    @AppStorage("secretFaceID", store: SharedStore.shared.defaults) private var useFaceID = false
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var confirmRotate = false
    @State private var info: String?

    var body: some View {
        Form {
            if let a = chat.account {
                Section("Profile") {
                    TextField("නම", text: $name).onSubmit { Task { await chat.updateProfile(name: name) } }
                    Text(PhoneNumber.display(a.phone)).foregroundStyle(.secondary)
                    Toggle("Phone number එකෙන් මාව හොයාගන්න දෙන්න", isOn: Binding(get: { a.discoverable }, set: { v in Task { await chat.updateProfile(discoverable: v) } }))
                    HStack { Text("Default country code  +"); TextField("94", text: $callingCode).keyboardType(.numberPad) }
                }
            }
            Section("Secret Chat") {
                NavigationLink(SecretPIN.shared.isSet ? "PIN එක වෙනස් කරන්න" : "PIN එකක් set කරන්න") { SetPINView(onDone: { info = "PIN එක save වුණා" }) }
                Toggle("App එකේ Face ID / Touch ID වලින් open කරන්න", isOn: $useFaceID)
                Text("Keyboard එකේ: 🔒 → PIN + phone number → Unlock. Keyboard එක වැහුණාම හරි 🔒 ඔබුවාම හරි ඉබේම lock වෙනවා.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Privacy සහ security") {
                Text("""
                Encrypt වෙන දේවල්: පණිවිඩවල text එක (HPKE / X25519 / ChaCha20-Poly1305, phone එකේදීම). Server එකට ඒවා කියවන්න බැහැ; deliver වුණාම server එකෙන් මැකෙනවා.
                Server එකට පේන දේවල්: ඔයාගේ නම, phone number එකේ hash එක, කවුද කාට කවදා පණිවිඩ යැව්වේ (metadata), Secret Chat invitations.
                Phone එකේ: chat history (encrypted database), keys, PIN hash — Keychain එකේ, මේ device එකට විතරයි.
                """).font(.footnote)
                Button("Safety: අනිත් devices sign out කරන්න") { Task { await chat.revokeOtherSessions(); info = "කළා" } }
                Button("Encryption key එක අලුත් කරන්න") { confirmRotate = true }
                Button("Phone එකේ chat history මකන්න") { chat.clearLocalCache(); info = "Local history මැකුවා" }
            }
            Section {
                Button("Sign out") { Task { await chat.signOut() } }
                Button("Account එක delete කරන්න", role: .destructive) { confirmDelete = true }
            }
            if let i = info { Text(i).foregroundStyle(.secondary) }
            if let e = chat.lastError { Text("Last error: \(e)").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Chat settings")
        .onAppear { name = chat.account?.displayName ?? "" }
        .confirmationDialog("Account එක delete කරන්නද? Server එකේ ඔයාගේ account එක, යවපු/නොලැබුණු පණිවිඩ මැකෙනවා. අනිත් අයගේ phones වල තියෙන history මැකෙන්නේ නැහැ.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await chat.signOut(deleteAccount: true) } }
        }
        .confirmationDialog("අලුත් key එකක් හැදුවම ඔයාගේ chats වල අනිත් අයට \"key changed\" warning එකක් පේනවා. Phone එක නැති වුණා / කවුරු හරි access කළා කියලා සැක නම් විතරක් කරන්න.", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("අලුත් key එකක් හදන්න") { Task { await chat.rotateIdentityKey() } }
        }
    }
}
