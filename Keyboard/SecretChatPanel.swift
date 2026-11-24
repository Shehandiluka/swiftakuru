import UIKit

/// While writing a Secret Chat reply, the keyboard's keys type into this private buffer instead of the
/// host app's text field. Singlish composition, suggestions and backspace all work as usual, because the
/// keyboard talks to whichever UITextDocumentProxy is active.
final class ChatDraftProxy: NSObject, UITextDocumentProxy {
    private(set) var text = ""
    var onChange: ((String) -> Void)?

    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    let documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }

    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .send
    var autocorrectionType: UITextAutocorrectionType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .sentences

    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) { insertText(markedText) }
    func unmarkText() {}
    func insertText(_ s: String) {
        guard text.count + s.count <= 4000 else { return }
        text += s; onChange?(text)
    }
    func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast(); onChange?(text)
    }
    func clear() { text = ""; onChange?(text) }
}

/// Strip shown above the suggestion bar while composing a Secret Chat reply.
final class SecretComposeStrip: UIView {
    let label = UILabel()
    let send = UIButton(type: .system)
    let cancel = UIButton(type: .system)
    var onSend: (() -> Void)?
    var onCancel: (() -> Void)?

    init(theme t: KBTheme, partner: String) {
        super.init(frame: .zero)
        backgroundColor = t.key.withAlphaComponent(0.9)
        layer.cornerRadius = 10
        label.font = .systemFont(ofSize: 15)
        label.textColor = t.keyText
        label.lineBreakMode = .byTruncatingHead
        label.text = "🔒 \(partner) ට reply…"
        label.alpha = 0.6
        cancel.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancel.tintColor = t.specialText
        send.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24)), for: .normal)
        send.tintColor = t.accent
        for v in [cancel, label, send] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), cancel.centerYAnchor.constraint(equalTo: centerYAnchor), cancel.widthAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: cancel.trailingAnchor, constant: 4), label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -6),
            send.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), send.centerYAnchor.constraint(equalTo: centerYAnchor), send.widthAnchor.constraint(equalToConstant: 36),
        ])
        send.addTarget(self, action: #selector(tapSend), for: .touchUpInside)
        cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)
        accessibilityLabel = "Secret Chat reply"
        send.accessibilityLabel = "Send"
        cancel.accessibilityLabel = "Cancel reply"
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ text: String, placeholder: String) {
        label.text = text.isEmpty ? placeholder : text
        label.alpha = text.isEmpty ? 0.6 : 1
    }
    @objc private func tapSend() { onSend?() }
    @objc private func tapCancel() { onCancel?() }
}

/// Secret Chat inside the keyboard: PIN + phone access pad, then the latest 5 messages of that chat.
/// The PIN and phone typed here never reach the host app; the PIN never leaves the device.
final class SecretChatPanel: UIView, ThemedPanel {
    weak var kb: KeyboardViewController?
    private var theme: KBTheme
    private let content = UIView()
    private var entry = ""
    private var timer: Timer?
    private(set) var conversationId: String?

    init(kb: KeyboardViewController, unlockedConversation: String? = nil) {
        self.kb = kb
        theme = kb.theme
        conversationId = unlockedConversation
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor)])
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }
    override func removeFromSuperview() { timer?.invalidate(); timer = nil; super.removeFromSuperview() }

    func applyTheme(_ t: KBTheme) { theme = t; render() }

    private var service: ChatService { ChatService.shared }

    private func render() {
        content.subviews.forEach { $0.removeFromSuperview() }
        guard let kb = kb else { return }
        if !kb.hasFullAccess { return message("Secret Chat එකට \"Allow Full Access\" ඕන.\nSettings → General → Keyboard → Keyboards → Swift Akuru → Allow Full Access.") }
        if !ChatCrypto.isSupported { return message("Secret Chat එකට iOS 17 හෝ ඊට අලුත් version එකක් ඕන.") }
        if !service.isSignedIn {
            return message(SharedStore.shared.hasAppGroup
                ? "මුලින්ම Swift Akuru app එකේ Chat tab එකෙන් account එකක් හදන්න."
                : "මේ install එකේ app ↔ keyboard share වෙන්නේ නැහැ (App Group නැහැ). SideStore එකෙන් install කරලා app එකේ Chat tab එකෙන් sign in වෙන්න.")
        }
        if !SecretPIN.shared.isSet { return message("App එකේ Chat → Secret Chat PIN එකක් set කරන්න.") }
        if let cid = conversationId, let c = service.db.conversation(cid), c.secret { showChat(c) } else { showAccess() }
    }

    private func message(_ text: String) {
        let l = UILabel()
        l.text = text; l.numberOfLines = 0; l.textAlignment = .center
        l.font = .systemFont(ofSize: 15); l.textColor = theme.specialText
        l.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(l)
        NSLayoutConstraint.activate([l.centerYAnchor.constraint(equalTo: content.centerYAnchor), l.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                                     l.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16)])
    }

    // MARK: access pad
    private let display = UILabel()
    private let hint = UILabel()

    private func showAccess() {
        timer?.invalidate(); timer = nil
        let len = SecretPIN.shared.length ?? 4
        display.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        display.textColor = theme.keyText
        display.textAlignment = .center
        display.backgroundColor = theme.key
        display.layer.cornerRadius = 10
        display.clipsToBounds = true
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = theme.specialText
        hint.textAlignment = .center
        hint.text = "PIN (ඉලක්කම් \(len)) + phone number → Unlock"
        updateDisplay()

        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 5; grid.distribution = .fillEqually
        let rows = [["1", "2", "3", "⌫"], ["4", "5", "6", "+"], ["7", "8", "9", "0"]]
        for r in rows {
            let h = UIStackView(); h.axis = .horizontal; h.spacing = 5; h.distribution = .fillEqually
            for k in r { h.addArrangedSubview(padKey(k)) }
            grid.addArrangedSubview(h)
        }
        let unlock = UIButton(type: .system)
        unlock.setTitle("🔓 Unlock", for: .normal)
        unlock.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        unlock.backgroundColor = theme.accent
        unlock.setTitleColor(.white, for: .normal)
        unlock.layer.cornerRadius = 8
        unlock.addTarget(self, action: #selector(tapUnlock), for: .touchUpInside)
        let bottom = UIStackView(arrangedSubviews: [unlock]); bottom.axis = .horizontal
        grid.addArrangedSubview(bottom)

        let v = UIStackView(arrangedSubviews: [display, hint, grid]); v.axis = .vertical; v.spacing = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: content.topAnchor, constant: 4), v.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -2),
                                     v.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6), v.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
                                     display.heightAnchor.constraint(equalToConstant: 34)])
        if case .locked(let until) = lockState() { showLocked(until) }
    }

    private func padKey(_ k: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(k, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 20, weight: .medium)
        b.setTitleColor(theme.keyText, for: .normal)
        b.backgroundColor = k == "⌫" || k == "+" ? theme.special : theme.key
        b.layer.cornerRadius = 8
        b.accessibilityLabel = k == "⌫" ? "Delete" : k
        b.addTarget(self, action: #selector(tapPad(_:)), for: .touchUpInside)
        return b
    }

    private func lockState() -> SecretPIN.Result? {
        let st = SecretPIN.shared.state
        if let u = st.lockedUntil, u > Date() { return .locked(until: u) }
        return nil
    }

    @objc private func tapPad(_ b: UIButton) {
        kb?.feedbackTick()
        guard let k = b.currentTitle else { return }
        if k == "⌫" { if !entry.isEmpty { entry.removeLast() } }
        else if entry.count < 24 { entry += k }
        updateDisplay()
    }

    private func updateDisplay() {
        let len = SecretPIN.shared.length ?? 4
        let pinPart = String(repeating: "•", count: min(entry.count, len))
        let rest = entry.count > len ? " " + String(entry.dropFirst(len)) : ""
        display.text = entry.isEmpty ? "••••  0771234567" : pinPart + rest
        display.alpha = entry.isEmpty ? 0.35 : 1
    }

    @objc private func tapUnlock() {
        let len = SecretPIN.shared.length ?? 4
        let input = entry
        entry = ""               // the command is never kept around
        updateDisplay()
        guard let parsed = SecretCommand.parse(input, pinLength: len, defaultCallingCode: service.defaultCallingCode) else {
            hint.text = "PIN (ඉලක්කම් \(len)) ගහලා ඊට පස්සේ phone number එක ගහන්න"
            return
        }
        hint.text = "බලනවා…"
        let pin = parsed.pin, phone = parsed.phone
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SecretPIN.shared.verify(pin)          // PBKDF2 off the main thread
            DispatchQueue.main.async { [weak self] in self?.handle(result, phone: phone) }
        }
    }

    private func handle(_ result: SecretPIN.Result, phone: String) {
        switch result {
        case .ok:
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let c = await self.service.secretConversation(forPhone: phone) {
                    self.conversationId = c.id
                    self.kb?.secretUnlocked(conversationId: c.id)
                    self.render()
                } else {
                    // Same message whether the number has no account or just isn't one of your Secret Chats.
                    self.hint.text = "ඒ number එකට Secret Chat එකක් නැහැ"
                }
            }
        case .wrong(let left):
            hint.text = left > 0 ? "PIN එක හරි නැහැ (තව \(left) පාරයි)" : "PIN එක හරි නැහැ"
        case .locked(let until):
            showLocked(until)
        case .notSet:
            render()
        }
    }

    private func showLocked(_ until: Date) {
        let secs = max(1, Int(until.timeIntervalSinceNow.rounded(.up)))
        hint.text = secs >= 60 ? "වැරදි PIN වැඩියි — විනාඩි \(Int((Double(secs) / 60).rounded(.up))) කින් ආයේ try කරන්න" : "වැරදි PIN වැඩියි — තත්පර \(secs) කින් ආයේ try කරන්න"
    }

    // MARK: chat (latest 5 messages)
    private func showChat(_ c: ChatConversation) {
        let header = UIStackView(); header.axis = .horizontal; header.spacing = 8; header.alignment = .center
        let avatar = UILabel()
        avatar.text = String(c.partnerName.prefix(1)).uppercased()
        avatar.textAlignment = .center; avatar.font = .systemFont(ofSize: 14, weight: .bold); avatar.textColor = .white
        avatar.backgroundColor = theme.accent; avatar.layer.cornerRadius = 13; avatar.clipsToBounds = true
        avatar.widthAnchor.constraint(equalToConstant: 26).isActive = true; avatar.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let name = UILabel()
        name.text = "🔒 " + c.partnerName + (c.keyChanged ? "  ⚠︎ key වෙනස් වෙලා" : "")
        name.font = .systemFont(ofSize: 15, weight: .semibold); name.textColor = c.keyChanged ? .systemOrange : theme.specialText
        let lock = UIButton(type: .system)
        lock.setImage(UIImage(systemName: "lock.fill"), for: .normal); lock.tintColor = theme.specialText
        lock.accessibilityLabel = "Lock Secret Chat"
        lock.addTarget(self, action: #selector(tapLock), for: .touchUpInside)
        header.addArrangedSubview(avatar); header.addArrangedSubview(name); header.addArrangedSubview(UIView()); header.addArrangedSubview(lock)

        let list = UIStackView(); list.axis = .vertical; list.spacing = 4
        let msgs = LatestMessages.latest(service.db.messages(conversationId: c.id, limit: 20))
        if msgs.isEmpty {
            let e = UILabel(); e.text = "තවම පණිවිඩ නැහැ"; e.textColor = theme.specialText; e.font = .systemFont(ofSize: 13); e.textAlignment = .center
            list.addArrangedSubview(e)
        }
        for m in msgs { list.addArrangedSubview(bubble(m)) }

        let reply = UIButton(type: .system)
        reply.setTitle("✏️ Reply", for: .normal)
        reply.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        reply.backgroundColor = theme.accent; reply.setTitleColor(.white, for: .normal); reply.layer.cornerRadius = 8
        reply.addTarget(self, action: #selector(tapReply), for: .touchUpInside)
        reply.isEnabled = !c.partnerDeleted
        let kbBtn = UIButton(type: .system)
        kbBtn.setTitle("⌨︎ Keyboard", for: .normal)
        kbBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        kbBtn.backgroundColor = theme.special; kbBtn.setTitleColor(theme.keyText, for: .normal); kbBtn.layer.cornerRadius = 8
        kbBtn.addTarget(self, action: #selector(tapLock), for: .touchUpInside)
        let bottom = UIStackView(arrangedSubviews: [reply, kbBtn]); bottom.axis = .horizontal; bottom.spacing = 6; bottom.distribution = .fillEqually

        let v = UIStackView(arrangedSubviews: [header, list, UIView(), bottom]); v.axis = .vertical; v.spacing = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: content.topAnchor, constant: 4), v.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -2),
                                     v.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8), v.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
                                     bottom.heightAnchor.constraint(equalToConstant: 34)])
        Task { @MainActor in await service.markRead(c.id) }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let cid = self.conversationId else { return }
                    let before = self.service.db.messages(conversationId: cid, limit: 5)
                    await self.service.sync()
                    if self.service.db.messages(conversationId: cid, limit: 5) != before { self.render() }
                }
            }
            Task { @MainActor [weak self] in await self?.service.sync(); self?.render() }
        }
    }

    private func bubble(_ m: ChatMessage) -> UIView {
        let l = UILabel()
        let t = Date(timeIntervalSince1970: TimeInterval(m.sentAt))
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(t) ? "HH:mm" : "d MMM HH:mm"
        let status: String
        switch m.status { case .pending: status = " ⏱"; case .failed: status = " ⚠︎"; case .sent: status = " ✓"; case .delivered: status = " ✓✓"; case .read: status = " ✓✓👁"; case .received: status = "" }
        l.text = m.text
        l.numberOfLines = 2
        l.font = .systemFont(ofSize: 14)
        l.textColor = m.outgoing ? .white : theme.keyText
        let time = UILabel()
        time.text = f.string(from: t) + (m.outgoing ? status : "")
        time.font = .systemFont(ofSize: 10)
        time.textColor = m.outgoing ? UIColor.white.withAlphaComponent(0.8) : theme.specialText
        let inner = UIStackView(arrangedSubviews: [l, time]); inner.axis = .horizontal; inner.spacing = 6; inner.alignment = .lastBaseline
        let box = UIView()
        box.backgroundColor = m.outgoing ? theme.accent : theme.key
        box.layer.cornerRadius = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        NSLayoutConstraint.activate([inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 4), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
                                     inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8)])
        let row = UIStackView(); row.axis = .horizontal
        if m.outgoing { row.addArrangedSubview(UIView()); row.addArrangedSubview(box) } else { row.addArrangedSubview(box); row.addArrangedSubview(UIView()) }
        box.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.82).isActive = true
        return row
    }

    @objc private func tapReply() {
        guard let cid = conversationId, let c = service.db.conversation(cid) else { return }
        timer?.invalidate(); timer = nil
        kb?.beginSecretCompose(conversationId: cid, partner: c.partnerName)
    }

    @objc private func tapLock() {
        timer?.invalidate(); timer = nil
        conversationId = nil
        kb?.lockSecretChat()
    }
}
