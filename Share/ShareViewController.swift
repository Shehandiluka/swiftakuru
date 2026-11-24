import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Swift Akuru" in the share sheet: share a chat message or a voice note → translation + reply.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        spinner.startAnimating()
        Task { @MainActor in
            let input = await loadInput()
            spinner.removeFromSuperview()
            show(input)
        }
    }

    private func show(_ input: TranslateView.Input) {
        let root = NavigationStack {
            Group {
                if SharedStore.shared.aiKey.isEmpty {
                    Text("Translate කරන්න AI key එකක් ඕන.\nSwift Akuru app → AI → Gemini key එක දාන්න (free: aistudio.google.com).")
                        .multilineTextAlignment(.center).padding()
                } else if input == .none {
                    Text("මේක translate කරන්න බැහැ. Text එකක් හෝ voice message එකක් share කරන්න.").multilineTextAlignment(.center).padding()
                } else {
                    TranslateView(input: input, inShareSheet: true) { [weak self] in self?.done() }
                }
            }
            .navigationTitle("🌐 Swift Akuru Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { [weak self] in self?.done() } } }
        }.tint(.purple)
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }

    private func done() { extensionContext?.completeRequest(returningItems: nil) }

    private static let audioExts: Set<String> = ["opus", "ogg", "oga", "m4a", "mp4", "aac", "mp3", "wav", "flac", "aiff", "aif", "caf", "amr", "webm"]

    private func loadInput() async -> TranslateView.Input {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        // 1) audio / files (voice notes)
        for p in providers {
            let types = p.registeredTypeIdentifiers
            let audioType = types.first { UTType($0)?.conforms(to: .audio) == true || UTType($0)?.conforms(to: .movie) == true }
                ?? types.first { t in Self.audioExts.contains(UTType(t)?.preferredFilenameExtension ?? "") }
                ?? (types.contains(UTType.fileURL.identifier) ? UTType.fileURL.identifier : nil)
            guard let type = audioType else { continue }
            if let url = await copyFile(p, type: type), Self.audioExts.contains(url.pathExtension.lowercased()) { return .audio(url) }
        }
        // 2) text
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                if let t = s as? String, !t.isEmpty { return .text(t) }
                if let d = s as? Data, let t = String(data: d, encoding: .utf8), !t.isEmpty { return .text(t) }
                if let u = s as? URL, let t = try? String(contentsOf: u), !t.isEmpty { return .text(t) }
            }
        }
        return .none
    }

    private func copyFile(_ p: NSItemProvider, type: String) async -> URL? {
        if type == UTType.fileURL.identifier {
            guard let item = try? await p.loadItem(forTypeIdentifier: type) else { return nil }
            let src = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let s = src else { return nil }
            return copy(s)
        }
        return await withCheckedContinuation { cont in
            _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in cont.resume(returning: url.flatMap { self.copy($0) }) }
        }
    }

    private func copy(_ src: URL) -> URL? {
        let ok = src.startAccessingSecurityScopedResource()
        defer { if ok { src.stopAccessingSecurityScopedResource() } }
        var name = src.lastPathComponent
        if src.pathExtension.isEmpty { name += ".m4a" }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        do { try FileManager.default.copyItem(at: src, to: dest); return dest } catch { return nil }
    }
}
