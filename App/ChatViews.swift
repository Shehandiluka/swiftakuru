import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import LocalAuthentication
import UniformTypeIdentifiers

// MARK: - Shared helpers
let swiftPurple = Color(red: 0.56, green: 0.40, blue: 1.0)
let inviteURL = URL(string: "https://swiftlk-site.shehandsandeep.workers.dev/download")!

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
    case "not_accepted": return "අනිත් කෙනා message request එක accept කරනකම් ඉන්න"
    case "not_found": return "හම්බ වුණේ නැහැ"
    case "too_large": return "File එක ලොකු වැඩියි (MB 24 උපරිමය)"
    case "media": return "File එක load කරන්න බැරි වුණා"
    default: return "Error: \(a.code)"
    }
}

func shortTime(_ t: Int) -> String {
    let d = Date(timeIntervalSince1970: TimeInterval(t))
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
    return f.string(from: d)
}
func timeOnly(_ t: Int) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date(timeIntervalSince1970: TimeInterval(t))) }
func lastSeenText(_ t: Int?) -> String? {
    guard let t = t else { return nil }
    let age = Date().timeIntervalSince1970 - Double(t)
    if age < 120 { return "online" }
    let d = Date(timeIntervalSince1970: TimeInterval(t))
    let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(d) ? "'today' HH:mm" : "d MMM HH:mm"
    return "last seen " + f.string(from: d)
}

struct Avatar: View {
    let name: String
    var base64: String? = nil
    var size: CGFloat = 40
    var body: some View {
        if let b = base64, let d = Data(base64Encoded: b), let img = UIImage(data: d) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(LinearGradient(colors: [swiftPurple, Color(white: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }
}

struct ContentUnavailableCompat: View {
    let title: String; let text: String; var symbol = "lock.shield"
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Wraps a chat screen: iOS check → registration → content.
struct ChatGate<Content: View>: View {
    @EnvironmentObject var chat: ChatService
    @ViewBuilder var content: () -> Content
    var body: some View {
        if !ChatCrypto.isSupported {
            ContentUnavailableCompat(title: "iOS 17 ඕන", text: "Swift Akuru Chat end-to-end encryption එකට iOS 17 හෝ ඊට අලුත් version එකක් ඕන.")
        } else if !chat.isSignedIn {
            RegisterView()
        } else {
            content()
        }
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
                Text("Swift Akuru Chat — Swift Akuru තියෙන අය එක්ක chat කරන්න. පණිවිඩ end-to-end encrypt වෙනවා; server එකට ඒවා කියවන්න බැහැ. OTP එක ඕන account එක හදද්දී විතරයි.").font(.subheadline)
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
                Text("දැනට SMS යවන්න test numbers විතරයි. ඔයාගේ phone number එක server එකේ තියෙන්නේ hash එකක් විදියට විතරයි.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Account හදන්න")
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

// MARK: - Chats tab
struct ChatsTab: View {
    @StateObject private var chat = ChatService.shared
    var body: some View {
        NavigationStack { ChatGate { ChatListView() } }
            .environmentObject(chat)
    }
}

struct ChatListView: View {
    @EnvironmentObject var chat: ChatService
    @State private var addToSecret: ChatConversation?
    @State private var reportTarget: ChatConversation?
    @State private var open: String?

    var all: [ChatConversation] { _ = chat.revision; return chat.db.conversations().filter { !$0.secret && !$0.hidden } }
    var requests: [ChatConversation] { all.filter { $0.isIncomingRequest(myId: chat.account?.id) } }
    var chats: [ChatConversation] { all.filter { !$0.isIncomingRequest(myId: chat.account?.id) } }
    var invitations: [ChatInvitation] { _ = chat.revision; return chat.db.invitations() }

    var body: some View {
        List {
            if !requests.isEmpty {
                Section("Message requests") {
                    ForEach(requests) { c in RequestRow(c: c, onOpen: { open = c.id }, onReport: { reportTarget = c }) }
                }
            }
            if !invitations.isEmpty {
                Section("Secret Chat invitations") { ForEach(invitations) { inv in InvitationRow(inv: inv) } }
            }
            Section {
                if chats.isEmpty { Text("තවම chats නැහැ. Search tab එකෙන් phone number එකෙන් හොයන්න.").foregroundStyle(.secondary) }
                ForEach(chats) { c in
                    NavigationLink(value: c.id) { ConversationRow(c: c) }
                        .contextMenu {
                            Button { open = c.id } label: { Label("Open Chat", systemImage: "bubble.left") }
                            if c.accepted { Button { addToSecret = c } label: { Label("Add to Secret Chat", systemImage: "lock") } }
                            Button { reportTarget = c } label: { Label("Report", systemImage: "exclamationmark.bubble") }
                            Button(role: .destructive) { Task { await chat.block(c) } } label: { Label("Block User", systemImage: "hand.raised") }
                            Button(role: .destructive) { Task { await chat.deleteConversation(c.id) } } label: { Label("Delete Conversation", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("Chats")
        .navigationDestination(for: String.self) { ChatThreadView(conversationId: $0) }
        .navigationDestination(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) { if let o = open { ChatThreadView(conversationId: o) } }
        .sheet(item: $addToSecret) { c in AddToSecretSheet(c: c).environmentObject(chat) }
        .sheet(item: $reportTarget) { c in ReportSheet(c: c).environmentObject(chat) }
        .refreshable { await chat.refreshConversations(); await chat.sync() }
        .task { await chat.refreshConversations(); await chat.loadProfile(); chat.startPolling(every: 5) }
        .onDisappear { chat.stopPolling() }
    }
}

struct RequestRow: View {
    @EnvironmentObject var chat: ChatService
    let c: ChatConversation
    var onOpen: () -> Void
    var onReport: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Avatar(name: c.partnerName, base64: c.partnerAvatar)
                VStack(alignment: .leading) {
                    Text(c.partnerName).font(.headline)
                    Text(chat.db.lastMessage(conversationId: c.id)?.preview ?? "ඔයාට message කරන්න කැමතියි").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                Button("Accept") { Task { await chat.acceptRequest(c.id); onOpen() } }.buttonStyle(.borderedProminent).tint(swiftPurple)
                Button("Block", role: .destructive) { Task { await chat.block(c) } }.buttonStyle(.bordered)
                Button("Report") { onReport() }.buttonStyle(.bordered)
                Button { Task { await chat.deleteConversation(c.id) } } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
            }.font(.subheadline)
        }.padding(.vertical, 4)
    }
}

struct ConversationRow: View {
    @EnvironmentObject var chat: ChatService
    let c: ChatConversation
    var body: some View {
        let last = chat.db.lastMessage(conversationId: c.id)
        let unread = chat.db.unreadCount(conversationId: c.id)
        HStack(spacing: 12) {
            Avatar(name: c.partnerName, base64: c.partnerAvatar)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(c.partnerName).font(.headline)
                    if c.secret { Image(systemName: "lock.fill").font(.caption).foregroundStyle(swiftPurple) }
                    if c.ttl > 0 { Image(systemName: "timer").font(.caption).foregroundStyle(.secondary) }
                    if c.keyChanged { Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                }
                if chat.isTyping(c.id) {
                    Text("typing…").font(.subheadline).foregroundStyle(swiftPurple)
                } else if !c.accepted && c.requestedBy == chat.account?.id {
                    Text("Request එක යැව්වා — accept කරනකම් ඉන්නවා").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(last.map { ($0.outgoing ? "ඔයා: " : "") + $0.preview } ?? "—").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let l = last { Text(shortTime(l.sentAt)).font(.caption2).foregroundStyle(.secondary) }
                if unread > 0 { Text("\(unread)").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(swiftPurple)) }
            }
        }
    }
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
                    Button("Accept") { Task { do { try await chat.respond(inv, accept: true) } catch { self.error = describe(error) } } }.buttonStyle(.borderedProminent).tint(swiftPurple)
                    Button("Decline") { Task { do { try await chat.respond(inv, accept: false) } catch { self.error = describe(error) } } }.buttonStyle(.bordered)
                }
            } else {
                Text("⏳ Secret Chat invitation එක යැව්වා — අනිත් කෙනා accept කරනකම් ඉන්නවා").font(.subheadline).foregroundStyle(.secondary)
            }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }
}

// MARK: - Search tab
struct SearchTab: View {
    @StateObject private var chat = ChatService.shared
    var body: some View {
        NavigationStack { ChatGate { SearchView() } }.environmentObject(chat)
    }
}

struct SearchView: View {
    @EnvironmentObject var chat: ChatService
    @State private var phone = ""
    @State private var result: ChatAPI.User?
    @State private var normalized: String?
    @State private var notFound = false
    @State private var message: String?
    @State private var busy = false
    @State private var open: String?

    var body: some View {
        Form {
            Section("Phone number එකෙන් හොයන්න") {
                TextField("+94771234567", text: $phone).keyboardType(.phonePad)
                Button(busy ? "හොයනවා…" : "Search") { Task { await search() } }.disabled(busy || phone.count < 7)
            }
            if let u = result {
                Section {
                    HStack(spacing: 12) { Avatar(name: u.displayName, base64: u.avatar, size: 52); Text(u.displayName).font(.title3.bold()) }
                    if u.acceptsRequests == false {
                        Text("මෙයා message requests ගන්නේ නැහැ.").foregroundStyle(.secondary)
                    } else {
                        Button("Message request එකක් යවන්න") { Task { await start(u) } }.buttonStyle(.borderedProminent).tint(swiftPurple)
                        Text("එයා accept කළාම chat කරන්න පුළුවන්. Block / report කරන්නත් එයාට පුළුවන්.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if notFound {
                Section {
                    Text("මේ number එක Swift Akuru එකේ නැහැ.").font(.headline)
                    ShareLink(item: inviteURL, message: Text("Swift Akuru එකෙන් chat කරමු — සිංහල keyboard + private chat. Download: ")) {
                        Label("Invite link එකක් යවන්න", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if let m = message { Section { Text(m).foregroundStyle(.secondary) } }
            Section {
                Text("Search කරන්න පුළුවන් පැයකට 20 පාරක් විතරයි (numbers scrape කරන එක නවත්වන්න). හංගලා තියෙන accounts මෙතන පේන්නේ නැහැ.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Search")
        .navigationDestination(isPresented: Binding(get: { open != nil }, set: { if !$0 { open = nil } })) { if let o = open { ChatThreadView(conversationId: o) } }
    }
    private func search() async {
        result = nil; message = nil; notFound = false
        guard let p = PhoneNumber.normalize(phone, defaultCallingCode: chat.defaultCallingCode) else { message = "Phone number එක හරි නැහැ"; return }
        busy = true; defer { busy = false }
        do {
            if let u = try await chat.lookup(phone: p) { result = u; normalized = p } else { notFound = true }
        } catch { message = describe(error) }
    }
    private func start(_ u: ChatAPI.User) async {
        do { open = try await chat.startConversation(with: u, phone: normalized) } catch { message = describe(error) }
    }
}

// MARK: - Thread
struct ChatThreadView: View {
    @EnvironmentObject var chat: ChatService
    let conversationId: String
    @State private var text = ""
    @State private var replyTo: ChatMessage?
    @State private var forwardItem: ChatMessage?
    @State private var showSafety = false
    @State private var showCustomTimer = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var sending = false
    @State private var showReport = false
    @State private var addSecret = false
    @StateObject private var recorder = VoiceRecorder()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var conv: ChatConversation? { _ = chat.revision; return chat.db.conversation(conversationId) }
    var msgs: [ChatMessage] { _ = chat.revision; return chat.db.messages(conversationId: conversationId) }
    var isRequestToMe: Bool { conv?.isIncomingRequest(myId: chat.account?.id) == true }
    var waitingForAccept: Bool { conv.map { !$0.accepted && $0.requestedBy == chat.account?.id } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            banners
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(msgs) { m in
                            MessageRow(m: m, onReply: { replyTo = m }, onForward: { forwardItem = m },
                                       onDeleteAll: { Task { await chat.deleteForEveryone(m) } }, onDeleteMe: { chat.deleteForMe(m) })
                                .id(m.id)
                        }
                    }.padding(.horizontal).padding(.top, 8)
                }
                .onChange(of: msgs.count) { _ in if let l = msgs.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                .onAppear { if let l = msgs.last { proxy.scrollTo(l.id, anchor: .bottom) } }
            }
            composer
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if conv?.secret == true { Image(systemName: "lock.fill").font(.caption).foregroundStyle(swiftPurple) }
                        Text(conv?.partnerName ?? "").font(.headline)
                    }
                    if chat.isTyping(conversationId) { Text("typing…").font(.caption).foregroundStyle(swiftPurple) }
                    else if let s = lastSeenText(conv?.lastSeen) { Text(s).font(.caption).foregroundStyle(.secondary) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .sheet(isPresented: $showSafety) { if let c = conv { SafetyNumberView(c: c).environmentObject(chat) } }
        .sheet(item: $forwardItem) { m in ForwardSheet(m: m).environmentObject(chat) }
        .sheet(isPresented: $showCustomTimer) { CustomTimerSheet { s in Task { await chat.setDisappearing(s, in: conversationId) } } }
        .sheet(isPresented: $showReport) { if let c = conv { ReportSheet(c: c).environmentObject(chat) } }
        .sheet(isPresented: $addSecret) { if let c = conv { AddToSecretSheet(c: c).environmentObject(chat) } }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { r in if case .success(let url) = r { Task { await sendFile(url) } } }
        .onChange(of: photoItem) { item in if let i = item { Task { await sendPhoto(i); photoItem = nil } } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if conv?.secret == true { Task { await chat.screenshotTaken(in: conversationId) } }
        }
        .onReceive(tick) { _ in chat.purgeExpired() }
        .task { await chat.sync(); if !isRequestToMe { await chat.markRead(conversationId) } }
        .onChange(of: chat.revision) { _ in if !isRequestToMe { Task { await chat.markRead(conversationId) } } }
    }

    @ViewBuilder private var banners: some View {
        if let c = conv, c.keyChanged {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("\(c.partnerName) ගේ encryption key එක වෙනස් වෙලා. Safety number එක check කරන්න.").font(.caption)
                Button("Check") { showSafety = true }.font(.caption.bold())
            }.padding(8).frame(maxWidth: .infinity).background(Color.orange.opacity(0.15))
        }
        if isRequestToMe, let c = conv {
            VStack(spacing: 6) {
                Text("\(c.partnerName) ඔයාට message request එකක් එව්වා. Accept කරනකම් (හෝ reply කරනකම්) එයාට ඔයා කියෙව්වද කියලා පේන්නේ නැහැ.").font(.caption).multilineTextAlignment(.center)
                HStack {
                    Button("Accept") { Task { await chat.acceptRequest(c.id) } }.buttonStyle(.borderedProminent).tint(swiftPurple)
                    Button("Block", role: .destructive) { Task { await chat.block(c) } }.buttonStyle(.bordered)
                    Button("Report") { showReport = true }.buttonStyle(.bordered)
                }.font(.caption)
            }.padding(8).frame(maxWidth: .infinity).background(swiftPurple.opacity(0.12))
        }
        if waitingForAccept {
            Text("Message request එක යැව්වා. එයා accept කරනකම් Secret Chat, typing වගේ දේවල් වැඩ කරන්නේ නැහැ.").font(.caption).foregroundStyle(.secondary).padding(6)
        }
        if let c = conv, c.ttl > 0 {
            Label("Disappearing messages: \(ChatService.ttlLabel(c.ttl))", systemImage: "timer").font(.caption).foregroundStyle(.secondary).padding(4)
        }
    }

    private var menu: some View {
        Menu {
            Menu {
                ForEach(Array(ChatService.ttlChoices.enumerated()), id: \.offset) { _, choice in
                    Button { Task { await chat.setDisappearing(choice.0, in: conversationId) } } label: {
                        if conv?.ttl == choice.0 { Label(choice.1, systemImage: "checkmark") } else { Text(choice.1) }
                    }
                }
                Button("Custom…") { showCustomTimer = true }
            } label: { Label("Disappearing messages", systemImage: "timer") }
            Button {
                Task { await chat.setKeepLast(conv?.keepLast == 5 ? 0 : 5, in: conversationId) }
            } label: { Label(conv?.keepLast == 5 ? "සියලු පණිවිඩ තියාගන්න" : "අන්තිම පණිවිඩ 5 විතරක් තියාගන්න", systemImage: "clock.arrow.circlepath") }
            Button { showSafety = true } label: { Label("Safety number", systemImage: "checkmark.shield") }
            if conv?.secret == true {
                Button { Task { await chat.leaveSecret(conversationId) } } label: { Label("Secret Chat එකෙන් අයින් කරන්න", systemImage: "lock.open") }
            } else if conv?.accepted == true {
                Button { addSecret = true } label: { Label("Add to Secret Chat", systemImage: "lock") }
            }
            Button { showReport = true } label: { Label("Report", systemImage: "exclamationmark.bubble") }
            if let c = conv { Button(role: .destructive) { Task { await chat.block(c) } } label: { Label("Block", systemImage: "hand.raised") } }
        } label: { Image(systemName: "ellipsis.circle") }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let r = replyTo {
                HStack {
                    Rectangle().fill(swiftPurple).frame(width: 3)
                    VStack(alignment: .leading) {
                        Text(r.outgoing ? "ඔයා" : (conv?.partnerName ?? "")).font(.caption.bold()).foregroundStyle(swiftPurple)
                        Text(r.preview).font(.caption).lineLimit(1)
                    }
                    Spacer()
                    Button { replyTo = nil } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
                }.padding(.horizontal).frame(height: 36)
            }
            if recorder.isRecording {
                HStack {
                    Image(systemName: "record.circle").foregroundStyle(.red)
                    Text("Recording… \(Int(recorder.elapsed))s").monospacedDigit()
                    Spacer()
                    Button("Cancel") { recorder.cancel() }
                    Button { Task { await sendVoice() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }.tint(swiftPurple)
                }.padding(.horizontal).padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    Menu {
                        PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) { Label("Photo / Video", systemImage: "photo") }
                        Button { showFiles = true } label: { Label("File", systemImage: "doc") }
                    } label: { Image(systemName: "plus.circle.fill").font(.system(size: 28)) }
                        .tint(swiftPurple).disabled(conv?.partnerDeleted == true || isRequestToMe)
                    TextField(sending ? "යවනවා…" : "Message", text: $text, axis: .vertical).lineLimit(1...5)
                        .padding(10).background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                        .onChange(of: text) { t in if !t.isEmpty, conv?.accepted == true { chat.userIsTyping(in: conversationId) } }
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { recorder.start() } label: { Image(systemName: "mic.circle.fill").font(.system(size: 32)) }
                            .tint(swiftPurple).disabled(conv?.partnerDeleted == true || isRequestToMe)
                    } else {
                        Button {
                            let t = text; let r = replyTo; text = ""; replyTo = nil
                            Task { await chat.send(t, in: conversationId, replyTo: r) }
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                            .tint(swiftPurple).disabled(conv?.partnerDeleted == true)
                    }
                }
            }
            if let e = chat.lastError, e == "too_large" || e == "media" { Text(describe(ChatAPI.APIError(status: 413, code: e))).font(.caption).foregroundStyle(.red) }
        }.padding(8)
    }

    // MARK: media sending
    private func sendPhoto(_ item: PhotosPickerItem) async {
        sending = true; defer { sending = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try? data.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let asset = AVURLAsset(url: tmp)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            let thumb = (try? gen.copyCGImage(at: .zero, actualTime: nil)).flatMap { MediaPrep.thumbnail(UIImage(cgImage: $0)) }
            let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) }
            await chat.sendMedia(data, mime: "video/quicktime", name: "video.mov", duration: dur, thumb: thumb, in: conversationId)
        } else if let img = UIImage(data: data), let jpeg = MediaPrep.jpeg(img, maxSide: 1600, quality: 0.75) {
            await chat.sendMedia(jpeg, mime: "image/jpeg", name: "photo.jpg", thumb: MediaPrep.thumbnail(img), in: conversationId)
        }
    }
    private func sendFile(_ url: URL) async {
        sending = true; defer { sending = false }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        await chat.sendMedia(data, mime: mime, name: url.lastPathComponent, in: conversationId)
    }
    private func sendVoice() async {
        guard let rec = recorder.stop() else { return }
        sending = true; defer { sending = false }
        await chat.sendMedia(rec.0, mime: "audio/m4a", name: "voice.m4a", duration: rec.1, in: conversationId)
    }
}

enum MediaPrep {
    static func jpeg(_ img: UIImage, maxSide: CGFloat, quality: CGFloat) -> Data? {
        let s = img.size
        let scale = min(1, maxSide / max(s.width, s.height))
        let size = CGSize(width: max(1, s.width * scale), height: max(1, s.height * scale))
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: quality)
    }
    static func thumbnail(_ img: UIImage) -> Data? { jpeg(img, maxSide: 64, quality: 0.5) }
}

struct MessageRow: View {
    @EnvironmentObject var chat: ChatService
    let m: ChatMessage
    var onReply: () -> Void
    var onForward: () -> Void
    var onDeleteAll: () -> Void
    var onDeleteMe: () -> Void

    var statusIcon: String {
        switch m.status {
        case .pending: return "clock"
        case .failed: return "exclamationmark.circle"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .received: return ""
        }
    }

    var body: some View {
        if m.kind == "system" {
            Text(m.text).font(.caption).foregroundStyle(.secondary).padding(.vertical, 4).frame(maxWidth: .infinity)
        } else {
            HStack {
                if m.outgoing { Spacer(minLength: 48) }
                bubble
                if !m.outgoing { Spacer(minLength: 48) }
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if m.forwarded && !m.deleted { Label("Forwarded", systemImage: "arrowshape.turn.up.right").font(.caption2).foregroundStyle(m.outgoing ? .white.opacity(0.8) : .secondary) }
            if let r = m.replyText, !m.deleted {
                HStack(spacing: 6) {
                    Rectangle().fill(m.outgoing ? Color.white.opacity(0.7) : swiftPurple).frame(width: 3)
                    Text(r).font(.caption).lineLimit(2)
                }.padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.12)))
            }
            if m.deleted {
                Text("🚫 මේ පණිවිඩය මකා දැමුවා").italic().foregroundStyle(m.outgoing ? .white.opacity(0.85) : .secondary)
            } else {
                if let media = m.media { MediaContent(ref: media, outgoing: m.outgoing) }
                if !m.text.isEmpty { Text(m.text).foregroundStyle(m.outgoing ? .white : .primary) }
            }
            HStack(spacing: 3) {
                if m.ttl != nil { Image(systemName: "timer").font(.caption2) }
                Text(timeOnly(m.sentAt)).font(.caption2)
                if m.outgoing { Image(systemName: statusIcon).font(.caption2) }
            }.foregroundStyle(m.outgoing ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18).fill(m.outgoing
            ? AnyShapeStyle(LinearGradient(colors: [swiftPurple, Color(red: 0.42, green: 0.30, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Color(.secondarySystemBackground))))
        .contextMenu {
            if !m.deleted {
                Button { onReply() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                if !m.text.isEmpty { Button { UIPasteboard.general.string = m.text } label: { Label("Copy", systemImage: "doc.on.doc") } }
                Button { onForward() } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            }
            Button(role: .destructive) { onDeleteMe() } label: { Label("Delete for me", systemImage: "trash") }
            if m.outgoing && !m.deleted { Button(role: .destructive) { onDeleteAll() } label: { Label("Delete for everyone", systemImage: "trash.slash") } }
        }
    }
}

/// Shows an attachment: downloads + decrypts on first view.
struct MediaContent: View {
    @EnvironmentObject var chat: ChatService
    let ref: ChatCrypto.MediaRef
    let outgoing: Bool
    @State private var url: URL?
    @State private var failed = false
    @State private var showVideo = false
    @StateObject private var player = AudioPlayback()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if failed { Text("Download වුණේ නැහැ").font(.caption).foregroundStyle(.red) }
        }
        .task { do { url = try await chat.mediaURL(ref) } catch { failed = true } }
    }

    @ViewBuilder private var content: some View {
        if ref.mime.hasPrefix("image/") {
            if let u = url, let img = UIImage(contentsOfFile: u.path) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 12))
            } else { placeholder }
        } else if ref.mime.hasPrefix("video/") {
            ZStack {
                placeholder
                Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundStyle(.white)
            }
            .onTapGesture { if url != nil { showVideo = true } }
            .sheet(isPresented: $showVideo) { if let u = url { VideoPlayer(player: AVPlayer(url: u)).ignoresSafeArea() } }
        } else if ref.mime.hasPrefix("audio/") {
            HStack {
                Button { if let u = url { player.toggle(u) } } label: { Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 30)) }
                    .foregroundStyle(outgoing ? .white : swiftPurple).disabled(url == nil)
                Text("🎤 " + (ref.duration.map { "\(Int($0.rounded()))s" } ?? "Voice")).foregroundStyle(outgoing ? .white : .primary)
            }
        } else {
            HStack {
                Image(systemName: "doc.fill").font(.title2)
                VStack(alignment: .leading) {
                    Text(ref.name ?? "File").lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(ref.size), countStyle: .file)).font(.caption)
                }
                if let u = url { ShareLink(item: u) { Image(systemName: "square.and.arrow.up") } }
            }.foregroundStyle(outgoing ? .white : .primary)
        }
    }

    @ViewBuilder private var placeholder: some View {
        if let t = ref.thumb, let d = Data(base64Encoded: t), let img = UIImage(data: d) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 200, height: 150).blur(radius: 6).clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.3)).frame(width: 200, height: 150).overlay(ProgressView())
        }
    }
}

final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    private var player: AVAudioPlayer?
    func toggle(_ url: URL) {
        if playing { player?.stop(); playing = false; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        playing = player?.play() ?? false
    }
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) { DispatchQueue.main.async { self.playing = false } }
}

final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("voice-draft.m4a") }

    func start() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { ok in
            DispatchQueue.main.async {
                guard ok else { return }
                try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try? session.setActive(true)
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1,
                                               AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
                self.recorder = try? AVAudioRecorder(url: self.url, settings: settings)
                guard self.recorder?.record() == true else { return }
                self.isRecording = true
                self.elapsed = 0
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    self.elapsed = self.recorder?.currentTime ?? 0
                    if self.elapsed > 300 { self.recorder?.pause() }        // 5 minute cap
                }
            }
        }
    }
    func stop() -> (Data, Double)? {
        let d = recorder?.currentTime ?? elapsed
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
        defer { try? FileManager.default.removeItem(at: url) }
        guard d > 0.5, let data = try? Data(contentsOf: url) else { return nil }
        return (data, d)
    }
    func cancel() { recorder?.stop(); recorder?.deleteRecording(); timer?.invalidate(); isRecording = false }
}

struct ForwardSheet: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let m: ChatMessage
    var targets: [ChatConversation] { chat.db.conversations().filter { !$0.hidden && $0.accepted && !$0.partnerDeleted } }
    var body: some View {
        NavigationStack {
            List(targets) { c in
                Button { Task { await chat.forward(m, to: c.id); dismiss() } } label: { ConversationRow(c: c) }
            }
            .navigationTitle("Forward to…")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct CustomTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSet: (Int) -> Void
    @State private var minutes = 10
    var body: some View {
        NavigationStack {
            Form {
                Stepper("විනාඩි \(minutes)", value: $minutes, in: 1...10080)
                Text("ලැබුණු පණිවිඩය කියෙව්වාට පස්සේ (යැවූ කෙනාගේ phone එකේ යැව්වාට පස්සේ) මේ කාලයෙන් මැකෙනවා. Phone එක offline නම් ඊළඟට open කළාම මැකෙනවා. Screenshot ගත්ත දේවල් මැකෙන්නේ නැහැ.").font(.footnote).foregroundStyle(.secondary)
                Button("Set") { onSet(minutes * 60); dismiss() }
            }
            .navigationTitle("Custom timer")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
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
                Text("\(c.partnerName) ගේ phone එකේ මේ chat එකේ තියෙන number එකත් මේකමද කියලා call එකකින් හරි මුණගැහිලා හරි බලන්න.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if c.keyChanged {
                    Button("Numbers එකයි — අලුත් key එක trust කරන්න") { chat.trustNewKey(c.id); dismiss() }.buttonStyle(.borderedProminent).tint(swiftPurple)
                }
                Spacer()
            }.padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Add to Secret Chat (PIN first, then mutual invitation)
struct AddToSecretSheet: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let c: ChatConversation
    @State private var pin = ""
    @State private var authed = false
    @State private var error: String?
    @State private var sent = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("🔒 \(c.partnerName) එක්ක chat එක Secret Chat එකක් කරන්නද?").font(.headline) }
                Section("මොකද වෙන්නේ") {
                    Text("• \(c.partnerName) ට invitation එකක් යනවා. එයා accept කළොත් විතරයි Secret Chat වෙන්නේ.")
                    Text("• Chat එක Chats list එකෙන් අයින් වෙලා Secret tab එකට යනවා (PIN / Face ID ඕන). Keyboard එකේ 🔒 එකෙනුත් open කරන්න පුළුවන්.")
                    Text("• පණිවිඩ කලින් වගේම end-to-end encrypted. Disappearing timer සහ \"අන්තිම 5 විතරක්\" chat එකේ ⋯ menu එකෙන්.")
                    Text("• හංගන එක encryption එකක් නෙවෙයි. Screenshots නවත්වන්න iOS ඉඩ දෙන්නේ නැහැ — app එකේදී screenshot එකක් ගත්තොත් අනිත් කෙනාට කියනවා විතරයි (keyboard එකේදී ඒකත් බැහැ).")
                }.font(.subheadline)
                if !SecretPIN.shared.isSet {
                    Section { NavigationLink("මුලින්ම Secret Chat PIN එකක් set කරන්න") { SetPINView(onDone: {}) } }
                } else if !authed {
                    Section("ඔයාගේ Secret Chat PIN එක") {
                        SecureField("PIN", text: $pin).keyboardType(.numberPad)
                        Button("Confirm") { confirmPIN() }
                    }
                } else {
                    Section {
                        Button(sent ? "Invitation එක යැව්වා ✓" : "Invitation එක යවන්න") {
                            Task { do { try await chat.inviteToSecret(c.id); sent = true } catch { self.error = describe(error) } }
                        }.disabled(sent)
                    }
                }
                if let e = error { Section { Text(e).foregroundStyle(.red) } }
            }
            .navigationTitle("Add to Secret Chat")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func confirmPIN() {
        let p = pin; pin = ""
        switch SecretPIN.shared.verify(p) {
        case .ok: authed = true; error = nil
        case .wrong: error = "PIN එක හරි නැහැ"
        case .locked: error = "PIN lock වෙලා — ටිකකින් ආයේ try කරන්න"
        case .notSet: break
        }
    }
}

struct ReportSheet: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let c: ChatConversation
    @State private var reason = "spam"
    @State private var details = ""
    @State private var alsoBlock = true
    var body: some View {
        NavigationStack {
            Form {
                Picker("හේතුව", selection: $reason) {
                    Text("Spam").tag("spam"); Text("Harassment").tag("harassment"); Text("Scam").tag("scam"); Text("වෙනත්").tag("other")
                }
                TextField("විස්තර (optional)", text: $details, axis: .vertical)
                Toggle("Block කරන්නත්", isOn: $alsoBlock)
                Text("Report එකට යන්නේ ඔයා ලියන හේතුව විතරයි. පණිවිඩ encrypted නිසා server එකට ඒවා කියවන්න බැහැ.").font(.footnote).foregroundStyle(.secondary)
                Button("Report \(c.partnerName)") {
                    Task {
                        await chat.reportUser(c, reason: reason + (details.isEmpty ? "" : ": " + details))
                        if alsoBlock { await chat.block(c) }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Report")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Secret tab (PIN gate)
struct SecretTab: View {
    @StateObject private var chat = ChatService.shared
    var body: some View {
        NavigationStack { ChatGate { SecretGateView() } }.environmentObject(chat)
    }
}

struct SecretGateView: View {
    @EnvironmentObject var chat: ChatService
    @AppStorage("secretFaceID", store: SharedStore.shared.defaults) private var useFaceID = false
    @Environment(\.scenePhase) private var phase
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
                    Section {
                        if secrets.isEmpty { Text("තවම Secret Chats නැහැ. Chats එකේ chat එකක් long-press කරලා \"Add to Secret Chat\" ඔබන්න.").foregroundStyle(.secondary) }
                        ForEach(secrets) { c in
                            NavigationLink { ChatThreadView(conversationId: c.id) } label: { ConversationRow(c: c) }
                                .swipeActions { Button("Leave") { Task { await chat.leaveSecret(c.id) } }.tint(.orange) }
                        }
                    }
                    Section { Button("🔒 Lock") { unlocked = false } }
                }
                .refreshable { await chat.refreshConversations(); await chat.sync() }
                .task { chat.startPolling(every: 5) }
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
        .navigationTitle("🔒 Secret")
        .onChange(of: phase) { p in if p != .active { unlocked = false; pin = "" } }     // locks when the app leaves the foreground
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
                Text("Secret Chat PIN එක ඔයාගේ phone එකේ විතරයි තියෙන්නේ. Server එකට යවන්නේ නැහැ. ඉලක්කම් 4–8ක් (1234, 0000 වගේ ලේසි ඒවා බැහැ).").font(.footnote)
            }
            if SecretPIN.shared.isSet { SecureField("දැන් තියෙන PIN එක", text: $current).keyboardType(.numberPad) }
            SecureField("අලුත් PIN", text: $pin).keyboardType(.numberPad)
            SecureField("ආයේ ගහන්න", text: $confirm).keyboardType(.numberPad)
            Button("PIN එක save කරන්න") { save() }
            if let m = message { Text(m).foregroundStyle(m.hasSuffix("✓") ? .green : .red) }
        }
        .navigationTitle("Secret Chat PIN")
    }
    private func save() {
        guard pin == confirm else { message = "PIN දෙක ගැළපෙන්නේ නැහැ"; return }
        guard SecretPIN.isAcceptable(pin) else { message = "ඉලක්කම් 4–8ක්, ලේසියෙන් අනුමාන කරන්න බැරි එකක් දාන්න"; return }
        if SecretPIN.shared.set(pin, current: SecretPIN.shared.isSet ? current : nil) {
            pin = ""; confirm = ""; current = ""; message = "Save වුණා ✓"; onDone()
        } else { message = "දැන් තියෙන PIN එක හරි නැහැ" }
    }
}

// MARK: - Settings tab
struct SettingsTab: View {
    @StateObject private var chat = ChatService.shared
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if chat.isSignedIn {
                        NavigationLink { ProfileView() } label: {
                            HStack(spacing: 12) {
                                Avatar(name: chat.account?.displayName ?? "?", base64: chat.me?.avatar, size: 48)
                                VStack(alignment: .leading) {
                                    Text(chat.account?.displayName ?? "").font(.headline)
                                    Text(PhoneNumber.display(chat.account?.phone ?? "")).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        NavigationLink { PrivacyView() } label: { Label("Privacy", systemImage: "hand.raised") }
                        NavigationLink { SecretSettingsView() } label: { Label("Secret Chat PIN / Face ID", systemImage: "lock") }
                        NavigationLink { SecurityView() } label: { Label("Security & account", systemImage: "checkmark.shield") }
                    } else {
                        NavigationLink { ChatGate { EmptyView() } } label: { Label("Chat account එකක් හදන්න", systemImage: "person.badge.plus") }
                    }
                }
                Section("Keyboard") {
                    NavigationLink { GuideView() } label: { Label("Singlish guide", systemImage: "character.book.closed") }
                    NavigationLink { ThemesView() } label: { Label("Themes", systemImage: "paintpalette") }
                    NavigationLink { AISettingsView() } label: { Label("Swift AI", systemImage: "sparkles") }
                    NavigationLink { MoreView() } label: { Label("Shortcuts, learned words, updates", systemImage: "ellipsis.circle") }
                }
                Section("Notifications") {
                    Text("Push notifications තවම නැහැ (Apple Developer account එකක් ඕන). App එක open කළාම පණිවිඩ එනවා. Push ආවම ඒකේ message එක පේන්නේ නැති වෙන විදියටයි හදන්නේ.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await chat.loadProfile() }
        }
        .environmentObject(chat)
    }
}

struct ProfileView: View {
    @EnvironmentObject var chat: ChatService
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Avatar(name: chat.account?.displayName ?? "?", base64: chat.me?.avatar, size: 96)
                        PhotosPicker(selection: $photo, matching: .images) { Text(busy ? "Upload වෙනවා…" : "Photo එක වෙනස් කරන්න") }
                        if chat.me?.avatar != nil { Button("Photo එක අයින් කරන්න", role: .destructive) { Task { await chat.setAvatar(nil) } }.font(.footnote) }
                    }
                    Spacer()
                }
            }
            Section("නම") {
                TextField("නම", text: $name)
                Button("Save") { Task { await chat.updateProfile(name: name.trimmingCharacters(in: .whitespaces)) } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Phone") { Text(PhoneNumber.display(chat.account?.phone ?? "")).foregroundStyle(.secondary) }
        }
        .navigationTitle("Profile")
        .onAppear { name = chat.account?.displayName ?? "" }
        .onChange(of: photo) { item in
            guard let item = item else { return }
            Task { await upload(item) }
        }
    }
    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false; photo = nil }
        guard let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
        var q: CGFloat = 0.7
        var jpeg = MediaPrep.jpeg(img, maxSide: 256, quality: q)
        while let j = jpeg, j.count > 60_000, q > 0.2 { q -= 0.15; jpeg = MediaPrep.jpeg(img, maxSide: 256, quality: q) }
        if let j = jpeg { await chat.setAvatar(j) }
    }
}

struct PrivacyView: View {
    @EnvironmentObject var chat: ChatService
    @State private var blocked: [ChatAPI.Blocked] = []
    var body: some View {
        Form {
            if let m = chat.me {
                Section {
                    Toggle("Phone number එකෙන් මාව හොයාගන්න දෙන්න", isOn: binding(m.discoverable, "discoverable"))
                    Toggle("අලුත් අයට message requests යවන්න දෙන්න", isOn: binding(m.allowRequests ?? true, "allowRequests"))
                } footer: { Text("Off කළොත් ඔයාගේ number එකෙන් search කරන කෙනාට \"Swift Akuru එකේ නැහැ\" කියලා පේනවා.") }
                Section {
                    Picker("Profile photo පේන්නේ", selection: pick(m.profileVisibility ?? "everyone", "profileVisibility")) {
                        Text("හැමෝටම").tag("everyone"); Text("Chat කරන අයට").tag("contacts"); Text("කාටවත් නැහැ").tag("nobody")
                    }
                    Picker("Last seen / online පේන්නේ", selection: pick(m.lastSeenVisibility ?? "contacts", "lastSeenVisibility")) {
                        Text("හැමෝටම").tag("everyone"); Text("Chat කරන අයට").tag("contacts"); Text("කාටවත් නැහැ").tag("nobody")
                    }
                    Toggle("Read receipts", isOn: binding(m.readReceipts ?? true, "readReceipts"))
                } footer: { Text("Read receipts off කළොත් ඔයාටත් අනිත් අයගේ read receipts පේන්නේ නැහැ.") }
            } else {
                ProgressView()
            }
            Section("Block කරපු අය") {
                if blocked.isEmpty { Text("කවුරුත් නැහැ").foregroundStyle(.secondary) }
                ForEach(blocked) { b in
                    HStack {
                        Text(b.displayName.isEmpty ? "User" : b.displayName)
                        Spacer()
                        Button("Unblock") { Task { await chat.unblock(b.id); blocked = await chat.blockedUsers() } }
                    }
                }
            }
        }
        .navigationTitle("Privacy")
        .task { await chat.loadProfile(); blocked = await chat.blockedUsers() }
    }
    private func binding(_ v: Bool, _ key: String) -> Binding<Bool> {
        Binding(get: { v }, set: { n in Task { await chat.updateSettings([key: n]) } })
    }
    private func pick(_ v: String, _ key: String) -> Binding<String> {
        Binding(get: { v }, set: { n in Task { await chat.updateSettings([key: n]) } })
    }
}

struct SecretSettingsView: View {
    @AppStorage("secretFaceID", store: SharedStore.shared.defaults) private var useFaceID = false
    @AppStorage("chatCallingCode", store: SharedStore.shared.defaults) private var callingCode = "94"
    var body: some View {
        Form {
            Section {
                NavigationLink(SecretPIN.shared.isSet ? "PIN එක වෙනස් කරන්න" : "PIN එකක් set කරන්න") { SetPINView(onDone: {}) }
                Toggle("App එකේ Face ID / Touch ID වලින් open කරන්න", isOn: $useFaceID)
            } footer: {
                Text("Keyboard එකේ: 🔒 → PIN + phone number → Unlock. Keyboard එක වැහුණාම ඉබේම lock වෙනවා. App එකේ Secret tab එක background එකට ගියාම lock වෙනවා.")
            }
            Section("Phone numbers") { HStack { Text("Default country code  +"); TextField("94", text: $callingCode).keyboardType(.numberPad) } }
        }
        .navigationTitle("Secret Chat")
    }
}

struct SecurityView: View {
    @EnvironmentObject var chat: ChatService
    @State private var confirmDelete = false
    @State private var confirmRotate = false
    @State private var info: String?
    var body: some View {
        Form {
            Section("Encrypt වෙන්නේ මොනවද") {
                Text("""
                Encrypt වෙනවා: පණිවිඩ, photos, videos, voice, files (phone එකේදීම; HPKE / X25519 / ChaCha20-Poly1305 සහ AES-256-GCM). Server එකට ඒවා කියවන්න බැහැ.
                Server එකට පේනවා: ඔයාගේ නම, profile photo (ඔයාගේ settings අනුව), phone number එකේ hash එක, කවුද කාට කවදා පණිවිඩ යැව්වේ, files වල size එක.
                Phone එකේ: history (encrypted database), keys, PIN hash — මේ device එකට විතරයි. Backup / recovery තවම නැහැ.
                """).font(.footnote)
            }
            Section {
                Button("අනිත් devices sign out කරන්න") { Task { await chat.revokeOtherSessions(); info = "කළා" } }
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
        .navigationTitle("Security")
        .confirmationDialog("Account එක delete කරන්නද? Server එකේ ඔයාගේ account එක, නොලැබුණු පණිවිඩ, files මැකෙනවා. අනිත් අයගේ phones වල තියෙන history මැකෙන්නේ නැහැ.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await chat.signOut(deleteAccount: true) } }
        }
        .confirmationDialog("අලුත් key එකක් හැදුවම අනිත් අයට \"key changed\" warning එකක් පේනවා.", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("අලුත් key එකක් හදන්න") { Task { await chat.rotateIdentityKey() } }
        }
    }
}
