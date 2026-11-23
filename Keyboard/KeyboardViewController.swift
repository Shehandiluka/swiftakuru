import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    let store = SharedStore.shared
    var theme = KBTheme.named("swift")

    let bgImage = UIImageView()
    let gradient = CAGradientLayer()
    let bar = SuggestionBar()
    let keys = KeyboardView()
    let panelHost = UIView()
    private var heightC: NSLayoutConstraint?
    private var keysHeightC: NSLayoutConstraint?
    var panel: UIView?

    var page: KeyPage = .letters
    var shift = 0                       // 0 off, 1 once, 2 caps lock
    var composing = ""                  // roman letters of the Singlish word being typed
    var composedShown = ""              // Sinhala currently shown as marked text
    var previousWord: String?
    private var lastSpaceTime: Date?
    private var autocorrected: (original: String, replacement: String)?
    private var deleteTimer: Timer?
    private var deleteCount = 0
    private var lastShiftTap = Date.distantPast
    private var lastDocumentId: UUID?
    private lazy var haptic = UIImpactFeedbackGenerator(style: .light)

    static let barHeight: CGFloat = 44
    var pendingUpdate: AppUpdate?

    /// Singlish is turned off automatically for e-mail / URL fields
    var singlish: Bool {
        guard store.layout == "singlish" else { return false }
        let kt = textDocumentProxy.keyboardType ?? .default
        return !(kt == .URL || kt == .emailAddress)
    }
    var live: Bool { store[bool: SharedStore.K.livePreview] }
    /// Every page (letters, numbers, අ pages, emoji, AI…) uses exactly this height, so the keyboard never jumps.
    var keyArea: CGFloat {
        let screen = UIScreen.main.bounds.size
        let landscape = screen.width > screen.height
        let h = CGFloat(store.keyHeight) * (landscape ? 0.76 : 1)
        return h * CGFloat(store[bool: SharedStore.K.numberRow] ? 5 : 4)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.applySettings() }
    }

    // MARK: lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = false
        gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradient, at: 0)
        bgImage.contentMode = .scaleAspectFill
        bgImage.clipsToBounds = true
        for v in [bgImage, bar, keys, panelHost] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        keys.overlay = view
        keys.onKey = { [weak self] s, e in self?.handle(s, e) }
        bar.onPick = { [weak self] s in self?.pickSuggestion(s) }
        bar.onTool = { [weak self] t in self?.tool(t) }
        NSLayoutConstraint.activate([
            bgImage.leadingAnchor.constraint(equalTo: view.leadingAnchor), bgImage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bgImage.topAnchor.constraint(equalTo: view.topAnchor), bgImage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.topAnchor.constraint(equalTo: view.topAnchor), bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            keys.leadingAnchor.constraint(equalTo: view.leadingAnchor), keys.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keys.topAnchor.constraint(equalTo: bar.bottomAnchor),
            panelHost.leadingAnchor.constraint(equalTo: view.leadingAnchor), panelHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelHost.topAnchor.constraint(equalTo: bar.bottomAnchor), panelHost.bottomAnchor.constraint(equalTo: keys.bottomAnchor),
        ])
        keysHeightC = keys.heightAnchor.constraint(equalToConstant: keyArea)
        keysHeightC?.isActive = true
        let h = view.heightAnchor.constraint(equalToConstant: Self.barHeight + keyArea + 4)
        h.priority = UILayoutPriority(999)
        h.isActive = true
        heightC = h
        panelHost.isHidden = true
        applySettings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySettings()
        if hasFullAccess { ClipboardStore.shared.capture() }
        let kt = textDocumentProxy.keyboardType ?? .default
        if ([.numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad] as [UIKeyboardType]).contains(kt) { page = .numbers; rebuildKeys() }
        updateAutoCap()
        refreshBar()
        pendingUpdate = UpdateChecker.cached()
        if hasFullAccess {
            Task { [weak self] in
                let u = await UpdateChecker.check()
                await MainActor.run { guard let self = self else { return }; if u != self.pendingUpdate { self.pendingUpdate = u; self.refreshBar() } }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        commitComposition()
        WordStore.shared.save()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }

    /// (re)reads settings: theme, layout, sizes
    func applySettings() {
        theme = KBTheme.named(store.themeId)
        if let g = theme.gradient { gradient.colors = g.map { $0.cgColor }; gradient.isHidden = false } else { gradient.isHidden = true }
        view.backgroundColor = theme.background
        if theme.id == "photo", let img = UIImage(contentsOfFile: store.customBackgroundURL.path) {
            bgImage.image = img; bgImage.isHidden = false
        } else { bgImage.image = nil; bgImage.isHidden = true }
        keys.theme = theme
        bar.theme = theme
        keysHeightC?.constant = keyArea
        heightC?.constant = Self.barHeight + keyArea + 4
        rebuildKeys()
        refreshBar()
        (panel as? ThemedPanel)?.applyTheme(theme)
    }

    func rebuildKeys() {
        let globe = needsInputModeSwitchKey
        let specs: [[KeySpec]]
        switch page {
        case .letters: specs = KeyLayout.letters(singlish: singlish, upper: shift > 0, numberRow: store[bool: SharedStore.K.numberRow], hints: store[bool: SharedStore.K.keyHints], showGlobe: globe)
        case .numbers, .symbols: specs = KeyLayout.numbersPage(symbols: page == .symbols, singlish: singlish, showGlobe: globe)
        case .sinhala1, .sinhala2, .sinhala3: specs = KeyLayout.sinhalaPage(page, showGlobe: globe)
        }
        keys.shiftState = shift
        keys.rowHeight = keyArea / CGFloat(max(1, specs.count))
        keys.setRows(specs)
        // return key label
        for b in keys.rows.flatMap({ $0 }) {
            if b.spec.kind == .ret { b.label.text = returnLabel() }
            if b.spec.kind == .globe { b.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents) }
        }
    }

    private func returnLabel() -> String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "go"
        case .search, .google, .yahoo: return "search"
        case .send: return "send"
        case .done: return "done"
        case .next: return "next"
        case .join: return "join"
        case .route: return "route"
        case .`continue`: return "continue"
        default: return "return"
        }
    }

    // MARK: key handling
    func handle(_ s: KeySpec, _ e: KeyboardView.Event) {
        switch e {
        case .down:
            feedback(s)
            if s.kind == .backspace { backspaceDown() }
        case .up:
            tap(s)
        case .alt(let a):
            typeAlt(a)
        case .cursor(let d):
            if !composing.isEmpty { commitComposition() }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: d)
            if store[bool: SharedStore.K.haptics], hasFullAccess { UISelectionFeedbackGenerator().selectionChanged() }
        case .cursorEnd:
            stopDelete()
            refreshBar()
        }
    }

    private func tap(_ s: KeySpec) {
        switch s.kind {
        case .char(let c): typeChar(c)
        case .space: space()
        case .ret:
            commitComposition()
            textDocumentProxy.insertText("\n")
            previousWord = nil
            updateAutoCap(); refreshBar()
        case .backspace: stopDelete()
        case .shift: shiftTap()
        case .globe: break
        case .emoji: showPanel(EmojiPanel(kb: self))
        case .lang:
            commitComposition()
            store.layout = store.layout == "singlish" ? "english" : "singlish"
            page = .letters; shift = 0
            rebuildKeys(); updateAutoCap(); refreshBar()
        case .page(let p):
            commitComposition()
            page = p
            rebuildKeys(); refreshBar()
        case .spacer: break
        }
    }

    private func shiftTap() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 { shift = 2 } else { shift = shift == 0 ? 1 : 0 }
        lastShiftTap = now
        rebuildKeys()
    }

    private func releaseShiftOnce() {
        if shift == 1 { shift = 0; rebuildKeys() }
    }

    func typeChar(_ c: String) {
        autocorrected = nil
        if singlish, page == .letters, c.count == 1, let ch = c.first, ch.isASCII, ch.isLetter {
            composing += c
            updateComposition()
            releaseShiftOnce()
            return
        }
        commitComposition()
        if !singlish, c.count == 1, ",.!?;:".contains(c) {
            // finishing an English word with punctuation → learn it
            let w = currentWord()
            if !w.isEmpty { WordStore.shared.learn(w, previous: previousWord); previousWord = w }
        }
        textDocumentProxy.insertText(c)
        if page == .letters { releaseShiftOnce() }
        if ".!?".contains(c) { previousWord = nil }
        updateAutoCap()
        refreshBar()
    }

    private func typeAlt(_ a: KeyAlt) {
        feedbackTick()
        if a.direct { typeCharDirect(a.value); return }
        composing += a.value
        updateComposition()
        releaseShiftOnce()
    }

    private func typeCharDirect(_ s: String) {
        commitComposition()
        textDocumentProxy.insertText(s)
        releaseShiftOnce()
        refreshBar()
    }

    // MARK: Singlish composition
    // The Sinhala word being typed is inserted as normal text and replaced in place on every key.
    // (Marked text behaves differently in each app — in some, the following space landed before the word.)
    func updateComposition() {
        let si = Singlish.convert(composing)
        if live { replaceTail(old: composedShown, with: si); composedShown = si }
        refreshBar()
    }

    func commitComposition(word: String? = nil) {
        guard !composing.isEmpty else { return }
        let w = word ?? Singlish.convert(composing)
        if live { replaceTail(old: composedShown, with: w) } else { textDocumentProxy.insertText(w) }
        WordStore.shared.learn(w, roman: composing, previous: previousWord)
        previousWord = w
        composing = ""
        composedShown = ""
    }

    private func cancelComposition() {
        if live && !composedShown.isEmpty { replaceTail(old: composedShown, with: "") }
        composing = ""; composedShown = ""
    }

    private static func str(_ s: ArraySlice<Unicode.Scalar>) -> String {
        var v = String.UnicodeScalarView()
        v.append(contentsOf: s)
        return String(v)
    }

    /// Replaces `old` (which is right before the cursor) with `new`, touching only the part that changed.
    private func replaceTail(old: String, with new: String) {
        guard old != new else { return }
        let proxy = textDocumentProxy
        let oldS = Array(old.unicodeScalars), newS = Array(new.unicodeScalars)
        var common = 0
        while common < oldS.count, common < newS.count, oldS[common] == newS[common] { common += 1 }
        let toRemove = oldS.count - common
        if toRemove > 0 {
            let before = Array((proxy.documentContextBeforeInput ?? "").unicodeScalars)
            if before.count >= oldS.count, Array(before.suffix(oldS.count)) == oldS {
                // delete until the context is short enough, then put back anything deleted too far
                let target = before.count - toRemove
                var current = before.count
                var steps = 0
                while current > target, steps < toRemove + 3 {
                    proxy.deleteBackward(); steps += 1
                    let now = (proxy.documentContextBeforeInput ?? "").unicodeScalars.count
                    if now >= current { break } // this app doesn't report changes right away
                    current = now
                }
                if current <= target {
                    if current < target { proxy.insertText(Self.str(before[current..<target])) }
                    if common < newS.count { proxy.insertText(Self.str(newS[common...])) }
                    return
                }
                // fallback: remove the rest of the old word (by characters) and type the new word in full
                let rest = old.count - steps
                if rest > 0 { for _ in 0..<rest { proxy.deleteBackward() } }
                proxy.insertText(new)
                return
            }
            // no usable context: replace the whole word
            for _ in 0..<old.count { proxy.deleteBackward() }
            proxy.insertText(new)
            return
        }
        if common < newS.count { proxy.insertText(Self.str(newS[common...])) }
    }

    // MARK: space / autocorrect / shortcuts
    private func space() {
        let shortcuts = store.shortcuts
        if !composing.isEmpty {
            if let exp = shortcuts[composing] {
                cancelComposition()
                textDocumentProxy.insertText(exp + " ")
            } else {
                let roman = composing
                commitComposition()
                textDocumentProxy.insertText(" ")
                bar.lastEmoji = store[bool: SharedStore.K.emojiSuggest] ? EmojiData.suggestions(for: roman) + EmojiData.suggestions(for: previousWord ?? "") : []
            }
            lastSpaceTime = Date()
            refreshBar()
            return
        }
        let word = currentWord()
        if !word.isEmpty, let exp = shortcuts[word] {
            for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(exp + " ")
            refreshBar(); return
        }
        // double space → ". "
        if store[bool: SharedStore.K.doubleSpace], let t = lastSpaceTime, Date().timeIntervalSince(t) < 0.9 {
            let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
            if ctx.hasSuffix(" "), let prev = ctx.dropLast().last, prev.isLetter || prev.isNumber || Singlish.isSinhala(String(prev)) {
                textDocumentProxy.deleteBackward()
                textDocumentProxy.insertText(". ")
                lastSpaceTime = nil
                previousWord = nil
                updateAutoCap(); refreshBar()
                return
            }
        }
        var finalWord = word
        if !singlish, store[bool: SharedStore.K.autocorrect], (textDocumentProxy.autocorrectionType ?? .default) != .no, word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "'" }) {
            let (_, corr) = WordStore.shared.englishSuggestions(partial: word)
            if let c = corr, c.lowercased() != word.lowercased() {
                replaceCurrentWord(word, with: c)
                autocorrected = (word, c)
                finalWord = c
            }
        }
        if !finalWord.isEmpty { WordStore.shared.learn(finalWord, previous: previousWord); previousWord = finalWord }
        textDocumentProxy.insertText(" ")
        lastSpaceTime = Date()
        bar.lastEmoji = store[bool: SharedStore.K.emojiSuggest] ? EmojiData.suggestions(for: finalWord) : []
        updateAutoCap()
        refreshBar()
    }

    private func replaceCurrentWord(_ word: String, with new: String) {
        for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(new)
    }

    /// letters right before the cursor (English / already committed text)
    func currentWord() -> String {
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        var w = ""
        for ch in ctx.reversed() {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "@" || ch == "\u{0DCA}" || ch == "\u{200D}" || Singlish.isSinhala(String(ch)) { w.insert(ch, at: w.startIndex) } else { break }
        }
        return w
    }

    // MARK: delete
    private func backspaceDown() {
        if let ac = autocorrected, (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(ac.replacement + " ") {
            for _ in 0..<(ac.replacement.count + 1) { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(ac.original)
            WordStore.shared.learn(ac.original, previous: nil) // never correct this word again
            WordStore.shared.learn(ac.original, previous: nil)
            autocorrected = nil
            refreshBar()
            return
        }
        autocorrected = nil
        deleteOnce()
        deleteCount = 0
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.deleteCount += 1
                if self.deleteCount > 20 { self.deleteWord() } else { self.deleteOnce() }
                self.feedbackTick()
            }
        }
    }

    private func stopDelete() {
        deleteTimer?.invalidate(); deleteTimer = nil
    }

    private func deleteOnce() {
        if !composing.isEmpty {
            composing.removeLast()
            if composing.isEmpty { cancelComposition(); refreshBar() } else { updateComposition() }
            return
        }
        textDocumentProxy.deleteBackward()
        updateAutoCap()
        refreshBar()
    }

    private func deleteWord() {
        if !composing.isEmpty { cancelComposition(); refreshBar(); return }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        var n = 0
        var seenWord = false
        for ch in ctx.reversed() {
            if ch == " " || ch == "\n" { if seenWord { break } } else { seenWord = true }
            n += 1
        }
        for _ in 0..<max(1, n) { textDocumentProxy.deleteBackward() }
        refreshBar()
    }

    // MARK: auto-capitalization
    func updateAutoCap() {
        guard page == .letters, !singlish, shift != 2 else { return }
        guard store[bool: SharedStore.K.autoCap], (textDocumentProxy.autocapitalizationType ?? .sentences) != .none else {
            if shift == 1 { shift = 0; rebuildKeys() }
            return
        }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = ctx.trimmingCharacters(in: .whitespaces)
        let want = ctx.isEmpty || ctx.hasSuffix("\n") || ((trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")) && ctx.hasSuffix(" "))
        let newShift = want ? 1 : 0
        if newShift != shift { shift = newShift; rebuildKeys() }
    }

    // MARK: suggestion bar
    func refreshBar() {
        if panel != nil { return }
        if !composing.isEmpty {
            var list = WordStore.shared.sinhalaSuggestions(roman: composing)
            if store[bool: SharedStore.K.emojiSuggest] { list += EmojiData.suggestions(for: composing).prefix(2) }
            bar.showSuggestions(list, primary: 0)
            return
        }
        if !singlish, page == .letters {
            let w = currentWord()
            if !w.isEmpty, !Singlish.isSinhala(w) {
                let (list, corr) = WordStore.shared.englishSuggestions(partial: w)
                var items = list
                if store[bool: SharedStore.K.emojiSuggest] { items += EmojiData.suggestions(for: w).prefix(2) }
                if !items.isEmpty {
                    bar.showSuggestions(items, primary: corr.flatMap { items.firstIndex(of: $0) } ?? -1)
                    return
                }
            }
        }
        // after a word: next-word predictions + emoji
        if let p = previousWord {
            let next = WordStore.shared.nextWords(after: p)
            let emo = Array(bar.lastEmoji.prefix(3))
            if !next.isEmpty || !emo.isEmpty { bar.showSuggestions(next + emo, primary: -1); return }
        }
        bar.showToolbar(clipboard: hasFullAccess && !ClipboardStore.shared.items.isEmpty, update: pendingUpdate != nil)
    }

    private func pickSuggestion(_ s: String) {
        feedbackTick()
        let isEmoji = s.unicodeScalars.first.map { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x2000 } ?? false
        if !composing.isEmpty {
            if isEmoji { commitComposition(); textDocumentProxy.insertText(" " + s); refreshBar(); return }
            commitComposition(word: s)
            textDocumentProxy.insertText(" ")
            lastSpaceTime = Date()
            bar.lastEmoji = []
            refreshBar()
            return
        }
        if isEmoji { textDocumentProxy.insertText(s); bar.lastEmoji = []; refreshBar(); return }
        let w = currentWord()
        if !w.isEmpty, !singlish {
            replaceCurrentWord(w, with: s)
        } else {
            textDocumentProxy.insertText(s)
        }
        textDocumentProxy.insertText(" ")
        WordStore.shared.learn(s, previous: previousWord)
        previousWord = s
        lastSpaceTime = Date()
        updateAutoCap()
        refreshBar()
    }

    // MARK: toolbar & panels
    private func tool(_ t: String) {
        feedbackTick()
        switch t {
        case "emoji": showPanel(EmojiPanel(kb: self))
        case "clipboard": showPanel(ClipboardPanel(kb: self))
        case "ai": showPanel(AIPanel(kb: self))
        case "settings": showPanel(SettingsPanel(kb: self))
        case "sinhala": commitComposition(); page = page.isSinhala ? .letters : .sinhala1; rebuildKeys()
        case "hide": dismissKeyboard()
        default: break
        }
    }

    func showPanel(_ p: UIView) {
        commitComposition()
        panel?.removeFromSuperview()
        panel = p
        p.translatesAutoresizingMaskIntoConstraints = false
        panelHost.addSubview(p)
        NSLayoutConstraint.activate([
            p.leadingAnchor.constraint(equalTo: panelHost.leadingAnchor), p.trailingAnchor.constraint(equalTo: panelHost.trailingAnchor),
            p.topAnchor.constraint(equalTo: panelHost.topAnchor), p.bottomAnchor.constraint(equalTo: panelHost.bottomAnchor),
        ])
        panelHost.isHidden = false
        keys.isHidden = true
        bar.showTitle(panelTitle(p)) { [weak self] in self?.closePanel() }
    }

    private func panelTitle(_ p: UIView) -> String {
        switch p {
        case is EmojiPanel: return "Emoji"
        case is ClipboardPanel: return "Clipboard"
        case is AIPanel: return "✨ Swift AI"
        case is SettingsPanel: return "Settings"
        default: return ""
        }
    }

    func closePanel() {
        panel?.removeFromSuperview()
        panel = nil
        panelHost.isHidden = true
        keys.isHidden = false
        refreshBar()
    }

    func insertFromPanel(_ s: String) {
        commitComposition()
        textDocumentProxy.insertText(s)
    }

    // MARK: feedback
    private func feedback(_ s: KeySpec) {
        if store[bool: SharedStore.K.sound] {
            let id: SystemSoundID = s.kind == .backspace ? 1155 : (s.isSpecial ? 1156 : 1104)
            AudioServicesPlaySystemSound(id)
        }
        feedbackTick()
    }
    func feedbackTick() {
        if store[bool: SharedStore.K.haptics], hasFullAccess { haptic.impactOccurred(intensity: 0.6) }
    }

    // MARK: UITextInputDelegate
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let docId = textDocumentProxy.documentIdentifier
        if docId != lastDocumentId {
            lastDocumentId = docId
            composing = ""; composedShown = ""; previousWord = nil
            let kt = textDocumentProxy.keyboardType ?? .default
            if ([.numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad] as [UIKeyboardType]).contains(kt) { page = .numbers } else if page == .numbers { page = .letters }
            rebuildKeys()
        }
        // the user moved the cursor / the app changed the text while a word was being composed
        if !composing.isEmpty, live, !composedShown.isEmpty {
            let shown = composedShown
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.composing.isEmpty, self.composedShown == shown else { return }
                if !(self.textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(shown) { self.composing = ""; self.composedShown = ""; self.refreshBar() }
            }
        }
        if hasFullAccess, ClipboardStore.shared.capture() { if composing.isEmpty { refreshBar() } }
        updateAutoCap()
    }
}
