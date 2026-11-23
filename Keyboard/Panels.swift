import UIKit

// MARK: - helpers
private func pill(_ title: String, theme t: KBTheme, filled: Bool = false, size: CGFloat = 14) -> UIButton {
    let b = UIButton(type: .system)
    b.setTitle(title, for: .normal)
    b.titleLabel?.font = .systemFont(ofSize: size, weight: .semibold)
    b.setTitleColor(filled ? .white : t.keyText, for: .normal)
    b.backgroundColor = filled ? t.accent : t.key
    b.layer.cornerRadius = 10
    b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    return b
}

private func infoLabel(_ text: String, theme t: KBTheme) -> UILabel {
    let l = UILabel()
    l.text = text
    l.numberOfLines = 0
    l.textAlignment = .center
    l.font = .systemFont(ofSize: 14)
    l.textColor = t.specialText
    return l
}

private func fullAccessMessage(_ t: KBTheme) -> UILabel {
    infoLabel("මේ feature එකට \"Allow Full Access\" ඕන.\nSettings → General → Keyboard → Keyboards → Swift Akuru → Allow Full Access ON කරන්න.\n(ඔයා type කරන දේවල් අපි කොහෙවත් යවන්නේ නැහැ — AI එකට යවන්නේ ඔයා AI button එක ඔබපු text එක විතරයි.)", theme: t)
}

// MARK: - Emoji
final class EmojiPanel: UIView, ThemedPanel, UICollectionViewDataSource, UICollectionViewDelegate {
    weak var kb: KeyboardViewController?
    private var theme: KBTheme
    private var collection: UICollectionView!
    private let cats = UIStackView()
    private var current: [String] = []
    private var catIndex = 0

    init(kb: KeyboardViewController) {
        self.kb = kb
        theme = kb.theme
        super.init(frame: .zero)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 40, height: 40)
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.scrollDirection = .vertical
        layout.sectionInset = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        collection.dataSource = self
        collection.delegate = self
        collection.translatesAutoresizingMaskIntoConstraints = false
        cats.axis = .horizontal
        cats.distribution = .fillEqually
        cats.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collection); addSubview(cats)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: topAnchor), collection.leadingAnchor.constraint(equalTo: leadingAnchor), collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: cats.topAnchor),
            cats.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), cats.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            cats.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2), cats.heightAnchor.constraint(equalToConstant: 36),
        ])
        var icons = ["🕘"] + EmojiData.categories.map { $0.icon }
        icons.append("⌫")
        for (i, ic) in icons.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(ic, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: ic == "⌫" ? 20 : 18)
            b.setTitleColor(theme.specialText, for: .normal)
            b.tag = i
            b.layer.cornerRadius = 8
            b.addTarget(self, action: #selector(tapCat(_:)), for: .touchUpInside)
            cats.addArrangedSubview(b)
        }
        let recent = SharedStore.shared.recentEmoji
        select(recent.isEmpty ? 1 : 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ t: KBTheme) { theme = t; collection.reloadData() }

    private func select(_ i: Int) {
        catIndex = i
        current = i == 0 ? SharedStore.shared.recentEmoji : EmojiData.categories[i - 1].emojis
        for v in cats.arrangedSubviews { v.backgroundColor = v.tag == i ? theme.key : .clear }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    @objc private func tapCat(_ b: UIButton) {
        if b.tag == EmojiData.categories.count + 1 { kb?.textDocumentProxy.deleteBackward(); kb?.feedbackTick(); return }
        select(b.tag)
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { current.count }
    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let c = cv.dequeueReusableCell(withReuseIdentifier: "e", for: ip) as! EmojiCell
        c.label.text = current[ip.item]
        return c
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        let e = current[ip.item]
        kb?.insertFromPanel(e)
        kb?.feedbackTick()
        var r = SharedStore.shared.recentEmoji
        r.removeAll { $0 == e }
        r.insert(e, at: 0)
        SharedStore.shared.recentEmoji = r
    }
}

final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        label.frame = contentView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Clipboard
final class ClipboardPanel: UIView, ThemedPanel, UITableViewDataSource, UITableViewDelegate {
    weak var kb: KeyboardViewController?
    private var theme: KBTheme
    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [ClipboardStore.Item] = []

    init(kb: KeyboardViewController) {
        self.kb = kb
        theme = kb.theme
        super.init(frame: .zero)
        guard kb.hasFullAccess else { addCentered(fullAccessMessage(theme)); return }
        ClipboardStore.shared.capture()
        items = ClipboardStore.shared.sorted
        table.backgroundColor = .clear
        table.separatorColor = theme.special
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 52
        table.translatesAutoresizingMaskIntoConstraints = false
        let clear = pill("Clear", theme: theme, size: 13)
        clear.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        clear.translatesAutoresizingMaskIntoConstraints = false
        let hint = UILabel()
        hint.text = "Tap = paste · swipe ← = pin / delete"
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = theme.hint
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(table); addSubview(clear); addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), hint.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), clear.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            table.topAnchor.constraint(equalTo: clear.bottomAnchor, constant: 2), table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor), table.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if items.isEmpty { addCentered(infoLabel("Copy කරපු දේවල් මෙතන save වෙනවා.\nමොනවා හරි copy කරලා බලන්න.", theme: theme)) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func addCentered(_ l: UILabel) {
        l.translatesAutoresizingMaskIntoConstraints = false
        addSubview(l)
        NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: centerXAnchor), l.centerYAnchor.constraint(equalTo: centerYAnchor), l.widthAnchor.constraint(equalTo: widthAnchor, constant: -32)])
    }

    func applyTheme(_ t: KBTheme) { theme = t; table.reloadData() }

    @objc private func clearAll() { ClipboardStore.shared.clearUnpinned(); items = ClipboardStore.shared.sorted; table.reloadData() }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let c = tv.dequeueReusableCell(withIdentifier: "c") ?? UITableViewCell(style: .default, reuseIdentifier: "c")
        let it = items[ip.row]
        c.backgroundColor = .clear
        c.textLabel?.text = (it.pinned ? "📌 " : "") + it.text.replacingOccurrences(of: "\n", with: " ")
        c.textLabel?.numberOfLines = 2
        c.textLabel?.font = .systemFont(ofSize: 15)
        c.textLabel?.textColor = theme.keyText
        c.selectedBackgroundView = UIView()
        c.selectedBackgroundView?.backgroundColor = theme.key
        return c
    }
    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        kb?.insertFromPanel(items[ip.row].text)
        kb?.feedbackTick()
    }
    func tableView(_ tv: UITableView, trailingSwipeActionsConfigurationForRowAt ip: IndexPath) -> UISwipeActionsConfiguration? {
        let it = items[ip.row]
        let del = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            ClipboardStore.shared.remove(it.text)
            self?.items = ClipboardStore.shared.sorted
            self?.table.reloadData()
            done(true)
        }
        let pin = UIContextualAction(style: .normal, title: it.pinned ? "Unpin" : "Pin") { [weak self] _, _, done in
            ClipboardStore.shared.togglePin(it.text)
            self?.items = ClipboardStore.shared.sorted
            self?.table.reloadData()
            done(true)
        }
        pin.backgroundColor = theme.accent
        return UISwipeActionsConfiguration(actions: [del, pin])
    }
}

// MARK: - AI
final class AIPanel: UIView, ThemedPanel {
    weak var kb: KeyboardViewController?
    private var theme: KBTheme
    private let sourceSeg = UISegmentedControl(items: ["ලියපු text", "Select කළ", "Clipboard"])
    private let actions = UIScrollView()
    private let actionStack = UIStackView()
    private let result = UITextView()
    private let replyStack = UIStackView()
    private let buttons = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var sourceText = ""
    private var lastAction: AIClient.Action?
    private var output = ""
    private var task: Task<Void, Never>?

    init(kb: KeyboardViewController) {
        self.kb = kb
        theme = kb.theme
        super.init(frame: .zero)
        guard kb.hasFullAccess else { addFill(fullAccessMessage(theme)); return }
        if SharedStore.shared.aiKey.isEmpty { buildNoKey(); return }
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ t: KBTheme) { theme = t }

    private func addFill(_ v: UIView, insets: CGFloat = 12) {
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets), v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets), v.topAnchor.constraint(equalTo: topAnchor, constant: 6), v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)])
    }

    private func buildNoKey() {
        let st = UIStackView()
        st.axis = .vertical; st.spacing = 10; st.alignment = .center
        st.addArrangedSubview(infoLabel("✨ Swift AI — translate, grammar fix, reply ideas, ask anything.\n\n1) aistudio.google.com එකෙන් FREE Gemini API key එකක් ගන්න\n2) Key එක copy කරලා පහළ button එක ඔබන්න", theme: theme))
        let b = pill("📋 Paste API key from clipboard", theme: theme, filled: true)
        b.addTarget(self, action: #selector(pasteKey), for: .touchUpInside)
        st.addArrangedSubview(b)
        addFill(st)
    }

    @objc private func pasteKey() {
        guard let k = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), k.count > 20, !k.contains(" ") else {
            kb?.bar.showSuggestions(["Clipboard එකේ API key එකක් නැහැ"], primary: -1); return
        }
        let st = SharedStore.shared
        let isOpenAI = k.hasPrefix("sk-")
        st[string: SharedStore.K.aiProvider] = isOpenAI ? "openai" : "gemini"
        st[string: isOpenAI ? SharedStore.K.aiKeyOpenAI : SharedStore.K.aiKeyGemini] = k
        subviews.forEach { $0.removeFromSuperview() }
        build()
    }

    private func build() {
        guard let kb = kb else { return }
        let proxy = kb.textDocumentProxy
        let selected = proxy.selectedText ?? ""
        sourceSeg.selectedSegmentIndex = selected.isEmpty ? 0 : 1
        sourceSeg.setEnabled(!selected.isEmpty, forSegmentAt: 1)
        sourceSeg.selectedSegmentTintColor = theme.accent
        sourceSeg.setTitleTextAttributes([.foregroundColor: theme.specialText, .font: UIFont.systemFont(ofSize: 12)], for: .normal)
        sourceSeg.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .selected)
        sourceSeg.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)

        actions.showsHorizontalScrollIndicator = false
        actionStack.axis = .horizontal
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actions.addSubview(actionStack)
        for (i, a) in AIClient.Action.allCases.enumerated() {
            let b = pill(a.title, theme: theme, size: 13)
            b.tag = i
            b.addTarget(self, action: #selector(runAction(_:)), for: .touchUpInside)
            actionStack.addArrangedSubview(b)
        }
        result.backgroundColor = theme.key.withAlphaComponent(0.6)
        result.textColor = theme.keyText
        result.font = .systemFont(ofSize: 15)
        result.isEditable = false
        result.layer.cornerRadius = 10
        result.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        replyStack.axis = .vertical
        replyStack.spacing = 4
        replyStack.isHidden = true
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually
        for (t, sel) in [("Replace", #selector(doReplace)), ("Insert", #selector(doInsert)), ("Copy", #selector(doCopy))] {
            let b = pill(t, theme: theme, filled: t == "Replace", size: 14)
            b.addTarget(self, action: sel, for: .touchUpInside)
            buttons.addArrangedSubview(b)
        }
        buttons.isHidden = true
        spinner.color = theme.accent
        spinner.hidesWhenStopped = true

        for v in [sourceSeg, actions, result, replyStack, buttons, spinner] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            sourceSeg.topAnchor.constraint(equalTo: topAnchor, constant: 2), sourceSeg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), sourceSeg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), sourceSeg.heightAnchor.constraint(equalToConstant: 28),
            actions.topAnchor.constraint(equalTo: sourceSeg.bottomAnchor, constant: 6), actions.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), actions.heightAnchor.constraint(equalToConstant: 34),
            actionStack.leadingAnchor.constraint(equalTo: actions.contentLayoutGuide.leadingAnchor), actionStack.trailingAnchor.constraint(equalTo: actions.contentLayoutGuide.trailingAnchor),
            actionStack.topAnchor.constraint(equalTo: actions.contentLayoutGuide.topAnchor), actionStack.bottomAnchor.constraint(equalTo: actions.contentLayoutGuide.bottomAnchor), actionStack.heightAnchor.constraint(equalTo: actions.frameLayoutGuide.heightAnchor),
            result.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 6), result.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), result.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            result.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -6),
            replyStack.topAnchor.constraint(equalTo: result.topAnchor), replyStack.leadingAnchor.constraint(equalTo: result.leadingAnchor), replyStack.trailingAnchor.constraint(equalTo: result.trailingAnchor),
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), buttons.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4), buttons.heightAnchor.constraint(equalToConstant: 34),
            spinner.centerXAnchor.constraint(equalTo: result.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: result.centerYAnchor),
        ])
        sourceChanged()
    }

    @objc private func sourceChanged() {
        guard let proxy = kb?.textDocumentProxy else { return }
        switch sourceSeg.selectedSegmentIndex {
        case 1: sourceText = proxy.selectedText ?? ""
        case 2: sourceText = UIPasteboard.general.string ?? ""
        default: sourceText = proxy.documentContextBeforeInput ?? ""
        }
        sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        output = ""
        buttons.isHidden = true
        replyStack.isHidden = true
        result.isHidden = false
        result.text = sourceText.isEmpty ? "මුලින්ම message එක type කරන්න (හෝ select / copy කරන්න), ඊට පස්සේ උඩ තියෙන action එකක් ඔබන්න." : "“\(sourceText.prefix(400))”"
        result.textColor = theme.hint
    }

    @objc private func runAction(_ b: UIButton) {
        let action = AIClient.Action.allCases[b.tag]
        guard !sourceText.isEmpty else { result.text = "Text එකක් නැහැ — මුලින්ම type කරන්න."; return }
        kb?.feedbackTick()
        lastAction = action
        task?.cancel()
        result.text = ""
        replyStack.isHidden = true
        result.isHidden = false
        buttons.isHidden = true
        spinner.startAnimating()
        let text = sourceText
        task = Task { [weak self] in
            do {
                let out = try await AIClient.run(action, text: text)
                await MainActor.run { self?.show(out, action: action) }
            } catch {
                await MainActor.run {
                    self?.spinner.stopAnimating()
                    self?.result.textColor = .systemRed
                    self?.result.text = error.localizedDescription
                }
            }
        }
    }

    private func show(_ out: String, action: AIClient.Action) {
        spinner.stopAnimating()
        output = out
        if action == .reply {
            result.isHidden = true
            replyStack.isHidden = false
            replyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for line in out.split(separator: "\n").map({ String($0).trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }).prefix(3) {
                let b = pill(line, theme: theme, size: 14)
                b.titleLabel?.numberOfLines = 2
                b.contentHorizontalAlignment = .left
                b.addTarget(self, action: #selector(insertReply(_:)), for: .touchUpInside)
                replyStack.addArrangedSubview(b)
            }
            return
        }
        result.textColor = theme.keyText
        result.text = out
        buttons.isHidden = false
    }

    @objc private func insertReply(_ b: UIButton) {
        if let t = b.title(for: .normal) { kb?.insertFromPanel(t); kb?.closePanel() }
    }

    @objc private func doReplace() {
        guard let kb = kb, !output.isEmpty else { return }
        let proxy = kb.textDocumentProxy
        switch sourceSeg.selectedSegmentIndex {
        case 0:
            // delete what we read before the cursor, then insert the result
            let before = (proxy.documentContextBeforeInput ?? "")
            let trailingSpaces = before.count - before.trimmingCharacters(in: .whitespacesAndNewlines).count
            let n = sourceText.count + max(0, trailingSpaces)
            for _ in 0..<n { proxy.deleteBackward() }
            proxy.insertText(output)
        case 1:
            proxy.insertText(output) // replaces the selection
        default:
            proxy.insertText(output)
        }
        kb.closePanel()
    }
    @objc private func doInsert() { guard !output.isEmpty else { return }; kb?.insertFromPanel(" " + output); kb?.closePanel() }
    @objc private func doCopy() { guard !output.isEmpty else { return }; UIPasteboard.general.string = output; kb?.bar.showSuggestions(["✓ Copied"], primary: 0) }
}

// MARK: - Settings (inside the keyboard, so it works even without the app)
final class SettingsPanel: UIView, ThemedPanel {
    weak var kb: KeyboardViewController?
    private var theme: KBTheme
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let store = SharedStore.shared

    init(kb: KeyboardViewController) {
        self.kb = kb
        theme = kb.theme
        super.init(frame: .zero)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -12),
        ])
        build()
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyTheme(_ t: KBTheme) { theme = t; stack.arrangedSubviews.forEach { $0.removeFromSuperview() }; build() }

    private func header(_ t: String) {
        let l = UILabel(); l.text = t; l.font = .systemFont(ofSize: 12, weight: .bold); l.textColor = theme.hint
        l.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(l)
    }

    private func toggle(_ title: String, _ key: String, rebuild: Bool = false) {
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .center
        let l = UILabel(); l.text = title; l.textColor = theme.keyText; l.font = .systemFont(ofSize: 15); l.numberOfLines = 2
        let sw = UISwitch(); sw.isOn = store[bool: key]; sw.onTintColor = theme.accent
        sw.accessibilityIdentifier = key
        sw.tag = rebuild ? 1 : 0
        sw.addTarget(self, action: #selector(switched(_:)), for: .valueChanged)
        row.addArrangedSubview(l); row.addArrangedSubview(sw)
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(row)
    }
    @objc private func switched(_ sw: UISwitch) {
        guard let k = sw.accessibilityIdentifier else { return }
        store[bool: k] = sw.isOn
        if sw.tag == 1 { kb?.applySettings() }
    }

    private func build() {
        header("THEME")
        let ts = UIScrollView(); ts.showsHorizontalScrollIndicator = false
        let tstack = UIStackView(); tstack.axis = .horizontal; tstack.spacing = 8; tstack.translatesAutoresizingMaskIntoConstraints = false
        ts.addSubview(tstack)
        for (i, t) in KBTheme.all.enumerated() {
            if t.id == "photo", !FileManager.default.fileExists(atPath: store.customBackgroundURL.path) { continue }
            let b = UIButton(type: .system)
            b.setTitle(t.name, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            b.setTitleColor(t.keyText, for: .normal)
            b.backgroundColor = t.background
            b.layer.cornerRadius = 10
            b.layer.borderWidth = t.id == store.themeId ? 3 : 1
            b.layer.borderColor = (t.id == store.themeId ? theme.accent : UIColor.gray).cgColor
            b.tag = i
            b.widthAnchor.constraint(equalToConstant: 92).isActive = true
            b.addTarget(self, action: #selector(pickTheme(_:)), for: .touchUpInside)
            tstack.addArrangedSubview(b)
        }
        NSLayoutConstraint.activate([
            tstack.leadingAnchor.constraint(equalTo: ts.contentLayoutGuide.leadingAnchor), tstack.trailingAnchor.constraint(equalTo: ts.contentLayoutGuide.trailingAnchor),
            tstack.topAnchor.constraint(equalTo: ts.contentLayoutGuide.topAnchor), tstack.bottomAnchor.constraint(equalTo: ts.contentLayoutGuide.bottomAnchor),
            tstack.heightAnchor.constraint(equalTo: ts.frameLayoutGuide.heightAnchor),
        ])
        ts.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(ts)

        header("KEY SIZE")
        let seg = UISegmentedControl(items: ["Small", "Medium", "Large"])
        let h = store.keyHeight
        seg.selectedSegmentIndex = h < 44 ? 0 : (h > 48 ? 2 : 1)
        seg.selectedSegmentTintColor = theme.accent
        seg.setTitleTextAttributes([.foregroundColor: theme.keyText], for: .normal)
        seg.addTarget(self, action: #selector(sizeChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(seg)

        header("TYPING")
        toggle("සිංහල live preview (type කරද්දිම)", SharedStore.K.livePreview)
        toggle("Keys උඩ සිංහල අකුරු පෙන්නන්න", SharedStore.K.keyHints, rebuild: true)
        toggle("Number row", SharedStore.K.numberRow, rebuild: true)
        toggle("English auto-correct", SharedStore.K.autocorrect)
        toggle("Auto capital letters", SharedStore.K.autoCap)
        toggle("Space දෙපාරක් = full stop", SharedStore.K.doubleSpace)
        toggle("Emoji suggestions", SharedStore.K.emojiSuggest)
        toggle("මම type කරන වචන ඉගෙනගන්න", SharedStore.K.learnWords)
        header("FEEDBACK (Full Access ඕන)")
        toggle("Key sound", SharedStore.K.sound)
        toggle("Vibration (haptics)", SharedStore.K.haptics)

        header("SWIFT AI")
        let ai = UISegmentedControl(items: ["Gemini (free)", "OpenAI"])
        ai.selectedSegmentIndex = store[string: SharedStore.K.aiProvider] == "openai" ? 1 : 0
        ai.selectedSegmentTintColor = theme.accent
        ai.setTitleTextAttributes([.foregroundColor: theme.keyText], for: .normal)
        ai.addTarget(self, action: #selector(aiChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(ai)
        let keyState = UILabel()
        keyState.text = store.aiKey.isEmpty ? "API key එකක් නැහැ" : "API key: ••••" + String(store.aiKey.suffix(4))
        keyState.textColor = theme.specialText
        keyState.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(keyState)
        let paste = pill("📋 Paste API key from clipboard", theme: theme)
        paste.addTarget(self, action: #selector(pasteKey), for: .touchUpInside)
        stack.addArrangedSubview(paste)

        header("DATA")
        let words = pill("ඉගෙනගත් වචන මකන්න (\(WordStore.shared.data.words.count))", theme: theme)
        words.addTarget(self, action: #selector(clearWords), for: .touchUpInside)
        stack.addArrangedSubview(words)
        let clip = pill("Clipboard history මකන්න", theme: theme)
        clip.addTarget(self, action: #selector(clearClip), for: .touchUpInside)
        stack.addArrangedSubview(clip)
        let about = UILabel()
        about.text = "Swift Akuru 1.0 · SwiftPayPOS (Pvt) Ltd · swiftlk.com"
        about.font = .systemFont(ofSize: 11)
        about.textColor = theme.hint
        about.textAlignment = .center
        about.heightAnchor.constraint(equalToConstant: 30).isActive = true
        stack.addArrangedSubview(about)
    }

    @objc private func pickTheme(_ b: UIButton) {
        store.themeId = KBTheme.all[b.tag].id
        kb?.applySettings()
        applyTheme(KBTheme.named(store.themeId))
    }
    @objc private func sizeChanged(_ s: UISegmentedControl) {
        store.keyHeight = [40.0, 46.0, 52.0][s.selectedSegmentIndex]
        kb?.applySettings()
    }
    @objc private func aiChanged(_ s: UISegmentedControl) {
        store[string: SharedStore.K.aiProvider] = s.selectedSegmentIndex == 1 ? "openai" : "gemini"
        applyTheme(theme)
    }
    @objc private func pasteKey() {
        guard kb?.hasFullAccess == true, let k = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), k.count > 20, !k.contains(" ") else { return }
        let openai = k.hasPrefix("sk-")
        store[string: SharedStore.K.aiProvider] = openai ? "openai" : "gemini"
        store[string: openai ? SharedStore.K.aiKeyOpenAI : SharedStore.K.aiKeyGemini] = k
        applyTheme(theme)
    }
    @objc private func clearWords() { WordStore.shared.forgetAll(); applyTheme(theme) }
    @objc private func clearClip() { ClipboardStore.shared.clearUnpinned(); applyTheme(theme) }
}
