import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// 🌐 Translate & Reply.
/// Copy (or select) a message from any chat → it is translated into your language → tap "Reply",
/// type your answer in Sinhala / Singlish / English → it goes into the chat in *their* language.
/// Voice messages: share the voice note to "Swift Akuru" (the share sheet) — keyboards cannot read audio.
final class TranslatePanel: UIView, ThemedPanel {
    weak var kb: KeyboardViewController?
    private var theme: KBTheme
    private let source = UISegmentedControl(items: ["📋 Copied", "Selected", "Typed"])
    private let langButton = UIButton(type: .system)
    private let result = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// Apple's own Paste button: reading the clipboard through it never shows the "Allow Paste?" question.
    private lazy var pasteButton: UIPasteControl = {
        let c = UIPasteControl.Configuration()
        c.displayMode = .iconAndLabel
        c.cornerStyle = .capsule
        c.baseBackgroundColor = theme.accent
        c.baseForegroundColor = .white
        let b = UIPasteControl(configuration: c)
        b.target = self
        return b
    }()
    private let buttons = UIStackView()
    private let picker = UIScrollView()
    private let pickerStack = UIStackView()
    private var pickerFor: PickerMode = .mine
    private enum PickerMode { case mine, reply }

    private var sourceText = ""
    private var last: Translator.Result?
    private var task: Task<Void, Never>?
    private static let speech = AVSpeechSynthesizer()

    init(kb: KeyboardViewController) {
        self.kb = kb
        theme = kb.theme
        super.init(frame: .zero)
        guard kb.hasFullAccess else { addFill(fullAccessMessage(theme)); return }
        guard !SharedStore.shared.aiKey.isEmpty else {
            addFill(infoLabel("🌐 Translate එකට AI key එකක් ඕන.\n✨ Swift AI → ‘Paste API key’ (free Gemini key: aistudio.google.com)", theme: theme)); return
        }
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func addFill(_ v: UIView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                                     v.topAnchor.constraint(equalTo: topAnchor, constant: 6), v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)])
    }

    private func build() {
        guard let kb = kb else { return }
        let selected = kb.textDocumentProxy.selectedText ?? ""
        source.setEnabled(!selected.isEmpty, forSegmentAt: 1)
        source.selectedSegmentIndex = !selected.isEmpty ? 1 : (UIPasteboard.general.hasStrings ? 0 : 2)
        source.selectedSegmentTintColor = theme.accent
        source.setTitleTextAttributes([.foregroundColor: theme.specialText, .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        source.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
        source.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)

        langButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        langButton.setTitleColor(.white, for: .normal)
        langButton.backgroundColor = theme.accent
        langButton.layer.cornerRadius = 8
        langButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        langButton.addTarget(self, action: #selector(pickMine), for: .touchUpInside)
        updateLangButton()

        result.backgroundColor = theme.key.withAlphaComponent(0.6)
        result.isEditable = false
        result.layer.cornerRadius = 10
        result.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        spinner.color = theme.accent
        spinner.hidesWhenStopped = true

        buttons.axis = .horizontal
        buttons.spacing = 6
        buttons.distribution = .fillProportionally
        for (t, sel, filled) in [("💬 Reply", #selector(reply), true), ("🌐▾", #selector(pickReply), false), ("🔊", #selector(listen), false),
                                 ("Copy", #selector(copyOut), false), ("Insert", #selector(insertOut), false)] {
            let b = pill(t, theme: theme, filled: filled, size: 14)
            b.addTarget(self, action: sel, for: .touchUpInside)
            buttons.addArrangedSubview(b)
        }

        picker.isHidden = true
        picker.backgroundColor = theme.background.withAlphaComponent(0.98)
        picker.layer.cornerRadius = 10
        pickerStack.axis = .vertical
        pickerStack.spacing = 6
        pickerStack.translatesAutoresizingMaskIntoConstraints = false
        picker.addSubview(pickerStack)

        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.plainText.identifier, UTType.utf8PlainText.identifier, UTType.text.identifier])
        pasteButton.isHidden = true
        for v in [source, langButton, result, spinner, pasteButton, buttons, picker] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            source.topAnchor.constraint(equalTo: topAnchor, constant: 2), source.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), source.heightAnchor.constraint(equalToConstant: 28),
            langButton.leadingAnchor.constraint(equalTo: source.trailingAnchor, constant: 6), langButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            langButton.centerYAnchor.constraint(equalTo: source.centerYAnchor), langButton.heightAnchor.constraint(equalToConstant: 28), langButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            result.topAnchor.constraint(equalTo: source.bottomAnchor, constant: 6), result.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), result.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            result.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -6),
            spinner.centerXAnchor.constraint(equalTo: result.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: result.centerYAnchor),
            pasteButton.centerXAnchor.constraint(equalTo: result.centerXAnchor), pasteButton.bottomAnchor.constraint(equalTo: result.bottomAnchor, constant: -10),
            pasteButton.heightAnchor.constraint(equalToConstant: 40), pasteButton.widthAnchor.constraint(equalToConstant: 150),
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), buttons.heightAnchor.constraint(equalToConstant: 34),
            picker.topAnchor.constraint(equalTo: topAnchor), picker.bottomAnchor.constraint(equalTo: bottomAnchor), picker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), picker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            pickerStack.topAnchor.constraint(equalTo: picker.contentLayoutGuide.topAnchor, constant: 6), pickerStack.bottomAnchor.constraint(equalTo: picker.contentLayoutGuide.bottomAnchor, constant: -6),
            pickerStack.leadingAnchor.constraint(equalTo: picker.contentLayoutGuide.leadingAnchor, constant: 6), pickerStack.trailingAnchor.constraint(equalTo: picker.contentLayoutGuide.trailingAnchor, constant: -6),
            pickerStack.widthAnchor.constraint(equalTo: picker.frameLayoutGuide.widthAnchor, constant: -12),
        ])
        // the panel is on screen first, then the clipboard is read (it may show iOS's paste question)
        DispatchQueue.main.async { [weak self] in self?.sourceChanged() }
    }

    func applyTheme(_ t: KBTheme) { theme = t }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let p = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = p.loadObject(ofClass: NSString.self) { [weak self] obj, _ in
            guard let s = (obj as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pasteButton.isHidden = true
                ClipboardStore.shared.add(s)
                self.sourceText = s
                self.run()
            }
        }
    }

    private func updateLangButton() { langButton.setTitle("→ \(Translator.myLanguage.native) ▾", for: .normal) }

    // MARK: source & translate
    @objc private func sourceChanged() {
        guard let kb = kb else { return }
        pasteButton.isHidden = true
        switch source.selectedSegmentIndex {
        case 0:
            // Reading the clipboard ourselves makes iOS ask "Allow Paste?" every time, unless the user turned on
            // Settings → Swift Akuru → Paste from Other Apps → Allow (then "auto save" is ON in our settings).
            if SharedStore.shared[bool: SharedStore.K.clipAuto] {
                sourceText = UIPasteboard.general.string ?? ""
            } else {
                last = nil
                guard UIPasteboard.general.hasStrings else {
                    show(note: "Chat එකේ message එක long-press → Copy කරලා මෙතනට එන්න. (Voice message: long-press → Share → Swift Akuru)")
                    return
                }
                show(note: "Copy කරපු message එක translate කරන්න පහළ Paste ඔබන්න 👇")
                pasteButton.isHidden = false
                return
            }
        case 1: sourceText = kb.textDocumentProxy.selectedText ?? ""
        default: sourceText = kb.textDocumentProxy.documentContextBeforeInput ?? ""
        }
        sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        last = nil
        guard !sourceText.isEmpty else {
            show(note: "Chat එකේ message එක long-press → Copy කරලා මෙතනට එන්න. (Voice message: long-press → Share → Swift Akuru)")
            return
        }
        run()
    }

    private func run() {
        task?.cancel()
        let text = String(sourceText.prefix(4000)), target = Translator.myLanguage
        Translator.touch(target)
        show(note: "")
        spinner.startAnimating()
        task = Task { [weak self] in
            do {
                let r = try await Translator.translate(text, to: target)
                await MainActor.run { self?.spinner.stopAnimating(); self?.last = r; self?.render() }
            } catch {
                await MainActor.run { self?.spinner.stopAnimating(); self?.show(note: error.localizedDescription, error: true) }
            }
        }
    }

    private func show(note: String, error: Bool = false) {
        result.attributedText = NSAttributedString(string: note, attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: error ? UIColor.systemRed : theme.hint])
    }

    private func render() {
        guard let r = last else { return }
        let out = NSMutableAttributedString()
        let from = r.source?.native ?? (r.sourceName.isEmpty ? "?" : r.sourceName)
        out.append(NSAttributedString(string: "\(from) → \(Translator.myLanguage.native)\n", attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: theme.accent]))
        out.append(NSAttributedString(string: r.translation + "\n", attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: theme.keyText]))
        out.append(NSAttributedString(string: sourceText.prefix(300) + (sourceText.count > 300 ? "…" : ""), attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: theme.hint]))
        result.attributedText = out
        result.setContentOffset(.zero, animated: false)
    }

    // MARK: actions
    @objc private func reply() {
        guard let kb = kb else { return }
        let target = replyTarget
        kb.beginTranslateReply(to: target, context: sourceText)
    }

    private var chosenReply: Translator.Language?
    private var replyTarget: Translator.Language {
        if let c = chosenReply { return c }
        if let s = last?.source, s != Translator.myLanguage { return s }
        return Translator.recent.first { $0 != Translator.myLanguage } ?? Translator.language("en")!
    }

    @objc private func listen() {
        guard let r = last else { return }
        let u = AVSpeechUtterance(string: r.translation)
        u.voice = AVSpeechSynthesisVoice(language: Translator.myLanguage.code)
        Self.speech.stopSpeaking(at: .immediate)
        Self.speech.speak(u)
    }
    @objc private func copyOut() {
        guard let r = last else { return }
        UIPasteboard.general.string = r.translation
        kb?.flash("✓ Copied")
    }
    @objc private func insertOut() {
        guard let r = last else { return }
        kb?.insertFromPanel(r.translation)
        kb?.closePanel()
    }

    // MARK: language picker (last used on top)
    @objc private func pickMine() { openPicker(.mine) }
    @objc private func pickReply() { openPicker(.reply) }

    private func openPicker(_ mode: PickerMode) {
        pickerFor = mode
        pickerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = UILabel()
        title.text = mode == .mine ? "Messages translate කරන්නේ මේ භාෂාවට:" : "Reply එක යවන්නේ මේ භාෂාවෙන්:"
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = theme.hint
        pickerStack.addArrangedSubview(title)
        let current = mode == .mine ? Translator.myLanguage : replyTarget
        var row: UIStackView?
        for (i, l) in Translator.ordered.enumerated() {
            if i % 3 == 0 {
                let r = UIStackView(); r.axis = .horizontal; r.spacing = 6; r.distribution = .fillEqually
                r.heightAnchor.constraint(equalToConstant: 34).isActive = true
                pickerStack.addArrangedSubview(r); row = r
            }
            let b = pill(l.native, theme: theme, filled: l == current, size: 14)
            b.tag = i
            b.addTarget(self, action: #selector(choose(_:)), for: .touchUpInside)
            row?.addArrangedSubview(b)
        }
        if let r = row { while r.arrangedSubviews.count < 3 { r.addArrangedSubview(UIView()) } }
        picker.setContentOffset(.zero, animated: false)
        picker.isHidden = false
    }

    @objc private func choose(_ b: UIButton) {
        let l = Translator.ordered[b.tag]
        picker.isHidden = true
        if pickerFor == .mine {
            Translator.myLanguage = l
            updateLangButton()
            if !sourceText.isEmpty { run() }
        } else {
            Translator.touch(l)
            chosenReply = l
            reply()
        }
    }
}
