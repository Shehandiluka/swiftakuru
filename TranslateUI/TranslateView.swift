import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Translate any message — text or a voice note — into your language, then write your reply
/// in Sinhala / Singlish / English and get it back in their language, ready to paste.
/// Used by the app's Translate tab and by the "Swift Akuru" share sheet.
struct TranslateView: View {
    enum Input: Equatable { case none, text(String), audio(URL) }

    @State var input: Input
    var inShareSheet = false
    var onDone: (() -> Void)?

    @State private var myLang = Translator.myLanguage
    @State private var result: Translator.Result?
    @State private var working = false
    @State private var error: String?
    @State private var pasted = ""
    @State private var replyText = ""
    @State private var replyLang: Translator.Language?
    @State private var replyOut = ""
    @State private var replying = false
    @State private var copied = false
    @State private var importing = false
    @StateObject private var recorder = TranslateRecorder()
    private let speech = AVSpeechSynthesizer()

    var body: some View {
        Form {
            if !inShareSheet { inputSection }
            if case .audio(let url) = input {
                Section { Label(url.lastPathComponent, systemImage: "waveform").font(.subheadline) } header: { Text("Voice message") }
            }
            Section {
                Menu {
                    ForEach(Translator.ordered, id: \.self) { l in
                        Button(l.label) { myLang = l; Translator.myLanguage = l; Task { await translate() } }
                    }
                } label: { HStack { Text("Translate කරන්නේ"); Spacer(); Text(myLang.native + " ▾").bold() } }
                if working { HStack { ProgressView(); Text(isAudio ? "Voice එක අහලා translate කරනවා…" : "Translate කරනවා…").foregroundStyle(.secondary) } }
                if let e = error { Text(e).foregroundStyle(.red).font(.subheadline) }
                if let r = result {
                    if let t = r.transcript {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("කිව්වේ (\(r.source?.native ?? r.sourceName))").font(.caption).foregroundStyle(.secondary)
                            Text(t).textSelection(.enabled)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(r.source?.native ?? r.sourceName) → \(myLang.native)").font(.caption.weight(.semibold)).foregroundStyle(.purple)
                        Text(r.translation).font(.title3.weight(.medium)).textSelection(.enabled)
                    }
                    HStack {
                        Button { speak(r.translation, myLang) } label: { Label("අහන්න", systemImage: "speaker.wave.2") }
                        Spacer()
                        Button { copy(r.translation) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }.buttonStyle(.borderless)
                }
            } header: { Text("Translation") }

            if result != nil {
                Section {
                    Menu {
                        ForEach(Translator.ordered, id: \.self) { l in Button(l.label) { replyLang = l; Translator.touch(l) } }
                    } label: { HStack { Text("Reply භාෂාව"); Spacer(); Text((targetForReply?.native ?? "තෝරන්න") + " ▾").bold() } }
                    TextField("ඔයාගේ reply එක (සිංහල / Singlish / English)", text: $replyText, axis: .vertical).lineLimit(2...6)
                    Button { Task { await translateReply() } } label: {
                        HStack { if replying { ProgressView() }; Text(replying ? "Translate කරනවා…" : "🌐 \(targetForReply?.native ?? "") වලට translate කරන්න") }
                    }.disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replying || targetForReply == nil)
                    if !replyOut.isEmpty {
                        Text(replyOut).font(.title3).textSelection(.enabled)
                        HStack {
                            Button { speak(replyOut, targetForReply ?? myLang) } label: { Label("අහන්න", systemImage: "speaker.wave.2") }
                            Spacer()
                            Button {
                                copy(replyOut)
                                if inShareSheet { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone?() } }
                            } label: { Label(inShareSheet ? "Copy කරලා chat එකට යන්න" : "Copy", systemImage: "doc.on.doc.fill") }
                        }.buttonStyle(.borderless)
                        Text("Chat එකට ගිහින් paste කරලා send කරන්න. (Swift Akuru keyboard එකේ 🌐 එකෙන් chat එක ඇතුළෙම reply කරන්නත් පුළුවන්)").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Reply") }
            }
            if copied { Text("✓ Copied").foregroundStyle(.green) }
        }
        .task { if result == nil, input != .none { await translate() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .data]) { r in
            if case .success(let url) = r {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
                input = .audio(dest); Task { await translate() }
            }
        }
    }

    private var isAudio: Bool { if case .audio = input { return true }; return false }
    private var targetForReply: Translator.Language? {
        if let l = replyLang { return l }
        if let s = result?.source, s != myLang { return s }
        return Translator.recent.first { $0 != myLang } ?? Translator.language("en")
    }

    @ViewBuilder private var inputSection: some View {
        Section {
            TextField("Message එක මෙතන paste කරන්න", text: $pasted, axis: .vertical).lineLimit(2...6)
            HStack {
                Button { if let s = UIPasteboard.general.string { pasted = s } } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Spacer()
                Button { input = .text(pasted); Task { await translate() } } label: { Label("Translate", systemImage: "character.bubble") }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.buttonStyle(.borderless)
            HStack {
                Button { importing = true } label: { Label("Voice file එකක්", systemImage: "waveform") }
                Spacer()
                Button {
                    if recorder.isRecording { if let u = recorder.stop() { input = .audio(u); Task { await translate() } } }
                    else { recorder.start() }
                } label: { Label(recorder.isRecording ? "නවත්තන්න" : "කතා කරන්න", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic") }
                    .tint(recorder.isRecording ? .red : .accentColor)
            }.buttonStyle(.borderless)
        } header: { Text("Message") } footer: {
            Text("WhatsApp / Viber voice message: long-press → Forward/Share → share icon → Swift Akuru. Chat එකේ text: keyboard එකේ 🌐.")
        }
    }

    private func translate() async {
        error = nil; result = nil; replyOut = ""; working = true
        defer { working = false }
        do {
            switch input {
            case .none: return
            case .text(let t):
                let t = t.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                result = try await Translator.translate(String(t.prefix(6000)), to: myLang)
            case .audio(let url):
                let data = try Data(contentsOf: url)
                guard data.count < 18_000_000 else { error = "Voice එක ලොකු වැඩියි (18MB උපරිමය)."; return }
                result = try await Translator.translateVoice(data, mime: Translator.mime(forExtension: url.pathExtension), to: myLang)
            }
            Translator.touch(myLang)
        } catch { self.error = error.localizedDescription }
    }

    private func translateReply() async {
        guard let lang = targetForReply else { return }
        replying = true; defer { replying = false }
        do {
            let ctx: String? = result?.transcript ?? { if case .text(let t) = input { return t }; return nil }()
            replyOut = try await Translator.reply(replyText, to: lang, context: ctx)
        } catch { self.error = error.localizedDescription }
    }

    private func copy(_ s: String) {
        UIPasteboard.general.string = s
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
    private func speak(_ s: String, _ l: Translator.Language) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: l.code)
        speech.stopSpeaking(at: .immediate)
        speech.speak(u)
    }
}

/// Records your own voice (app only) so you can speak and get it translated.
final class TranslateRecorder: ObservableObject {
    @Published var isRecording = false
    private var rec: AVAudioRecorder?
    private var url: URL?

    func start() {
        let s = AVAudioSession.sharedInstance()
        s.requestRecordPermission { ok in
            guard ok else { return }
            DispatchQueue.main.async {
                try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try? s.setActive(true)
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("speak-\(UUID().uuidString).m4a")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
                self.rec = try? AVAudioRecorder(url: u, settings: settings)
                self.url = u
                self.isRecording = self.rec?.record() ?? false
            }
        }
    }
    func stop() -> URL? {
        rec?.stop(); rec = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }
}
