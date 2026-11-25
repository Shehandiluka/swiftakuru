import UIKit

final class KeyButton: UIControl {
    var spec: KeySpec
    let label = UILabel()
    let hintLabel = UILabel()
    let icon = UIImageView()
    let bg = UIView()

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        bg.isUserInteractionEnabled = false
        bg.layer.cornerRadius = 8
        bg.layer.shadowOffset = CGSize(width: 0, height: 1)
        bg.layer.shadowRadius = 0
        bg.layer.shadowOpacity = 1
        addSubview(bg)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.isUserInteractionEnabled = false
        hintLabel.textAlignment = .right
        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.isUserInteractionEnabled = false
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        bg.addSubview(label); bg.addSubview(hintLabel); bg.addSubview(icon)
        isAccessibilityElement = true
        accessibilityLabel = spec.label
        accessibilityTraits = .keyboardKey
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        bg.frame = bounds.insetBy(dx: 3, dy: 5.5)
        label.frame = bg.bounds.insetBy(dx: 2, dy: 0)
        hintLabel.frame = CGRect(x: 0, y: 1, width: bg.bounds.width - 4, height: 12)
        icon.frame = bg.bounds
        bg.layer.shadowPath = UIBezierPath(roundedRect: bg.bounds.offsetBy(dx: 0, dy: 1), cornerRadius: 8).cgPath
    }

    func apply(theme t: KBTheme, highlighted: Bool = false, active: Bool = false) {
        let special = spec.isSpecial
        var color = special ? t.special : t.key
        if active { color = t.accent }
        if highlighted { color = special ? t.key : t.special }
        bg.backgroundColor = color
        bg.layer.shadowColor = t.shadow.cgColor
        label.textColor = active ? .white : (special ? t.specialText : t.keyText)
        icon.tintColor = active ? .white : t.specialText
        hintLabel.textColor = t.hint
    }

    /// Subtle press animation (skipped when Reduce Motion is on).
    func animatePress(_ down: Bool) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(withDuration: down ? 0.05 : 0.14, delay: 0, usingSpringWithDamping: down ? 1 : 0.6, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.bg.transform = down ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
        }
    }

    // A slightly larger hit area to make typing forgiving
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -2, dy: -3).contains(point) }
}

/// Lays out rows of keys and reports key events.
final class KeyboardView: UIView {
    enum Event { case down, up, alt(KeyAlt), cursor(Int), cursorEnd }
    var onKey: ((KeySpec, Event) -> Void)?
    weak var overlay: UIView?
    var theme = KBTheme.named("swift")
    var rowHeight: CGFloat = 53
    private(set) var rows: [[KeyButton]] = []
    private var bubble: UILabel?
    private var altView: UIStackView?
    private var altChoices: [KeyAlt] = []
    private var altIndex = 0
    var shiftState = 0 // 0 off, 1 on, 2 lock
    fileprivate var glowState: (timer: Timer?, step: Int, cycles: Int, lit: KeyButton?) = (nil, 0, 0, nil)
    /// Returns P(next letter) from the personal language model, or nil when smart touch is off.
    var nextLetterProbability: ((String) -> Double?)?

    /// Smart touch: the system keyboard trick — when a finger lands near the edge between letter keys, the touch goes to
    /// the key that combines "how close" (a 2-D Gaussian around each key centre) with "how likely next" (letter model).
    /// A tap clearly inside a key always stays on that key.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        guard let b = hit as? KeyButton, case .char(let c0) = b.spec.kind, c0.count == 1, altView == nil,
              let prob = nextLetterProbability, let p0 = prob(c0.lowercased()) else { return hit }
        var best = b, bestScore = -1.0
        for k in rows.flatMap({ $0 }) where !k.isHidden {
            guard case .char(let c) = k.spec.kind, c.count == 1, c.first?.isLetter == true else { continue }
            let f = k.frame, w = max(f.width, 1), h = max(f.height, 1)
            guard f.insetBy(dx: -w * 0.3, dy: -h * 0.15).contains(point) else { continue }
            let dx = (point.x - f.midX) / (w * 0.45), dy = (point.y - f.midY) / (h * 0.55)
            let spatial = exp(-(dx * dx + dy * dy) / 2)
            let pk = k === b ? p0 : (prob(c.lowercased()) ?? 0)
            let score = spatial * pow(max(pk, 1e-6), 0.5)
            if score > bestScore { bestScore = score; best = k }
        }
        return best
    }

    var nameGlowEnabled = true { didSet { if !nameGlowEnabled { stopNameGlow() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Keys whose finger is still down, in the order they were pressed (fast "rolling" typing).
    private var held: [KeyButton] = []
    /// Keys already typed early because the next key was pressed first; their own touch-up is ignored.
    private var consumed = Set<ObjectIdentifier>()

    func setRows(_ specs: [[KeySpec]]) {
        stopNameGlow()
        defer { scheduleNameGlow() }
        // Same shape (e.g. shift / auto-capital changed): keep the existing key views and only swap
        // what they type. Replacing them would drop a finger that is already down on a key.
        if rows.count == specs.count, zip(rows, specs).allSatisfy({ $0.count == $1.count && zip($0, $1).allSatisfy { sameKind($0.spec.kind, $1.kind) } }) {
            for (r, row) in specs.enumerated() { for (i, sp) in row.enumerated() { update(rows[r][i], to: sp) } }
            setNeedsLayout()
            refreshStyle()
            return
        }
        rows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        held.removeAll(); consumed.removeAll()
        rows = specs.map { row in row.map { makeKey($0) } }
        setNeedsLayout()
        refreshStyle()
    }

    private func sameKind(_ a: KeyKind, _ b: KeyKind) -> Bool {
        switch (a, b) {
        case (.char, .char): return true
        default: return a == b
        }
    }

    private func update(_ b: KeyButton, to s: KeySpec) {
        let hadAlts = !b.spec.alts.isEmpty
        b.spec = s
        b.accessibilityLabel = s.label
        if hadAlts != !s.alts.isEmpty {
            b.gestureRecognizers?.filter { $0 is UILongPressGestureRecognizer }.forEach { b.removeGestureRecognizer($0) }
            if !s.alts.isEmpty { addLongPress(b) }
        }
    }

    private func makeKey(_ s: KeySpec) -> KeyButton {
        let b = KeyButton(spec: s)
        if case .spacer = s.kind { b.isHidden = true }
        addSubview(b)
        b.addTarget(self, action: #selector(down(_:)), for: .touchDown)
        b.addTarget(self, action: #selector(up(_:)), for: .touchUpInside)
        b.addTarget(self, action: #selector(cancel(_:)), for: [.touchUpOutside, .touchCancel])
        if !s.alts.isEmpty { addLongPress(b) }
        if case .space = s.kind {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(spacePan(_:)))
            pan.delegate = self
            b.addGestureRecognizer(pan)
        }
        return b
    }

    private func addLongPress(_ b: KeyButton) {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        lp.minimumPressDuration = 0.4
        lp.cancelsTouchesInView = true
        b.addGestureRecognizer(lp)
    }

    /// Keys that type something on release and can be "rolled" over by the next key.
    private func isTyping(_ b: KeyButton) -> Bool {
        switch b.spec.kind {
        case .char, .space: return true
        default: return false
        }
    }

    func refreshStyle() {
        for b in rows.flatMap({ $0 }) {
            let s = b.spec
            var active = false
            switch s.kind {
            case .shift:
                active = shiftState > 0
                b.icon.image = UIImage(systemName: shiftState == 2 ? "capslock.fill" : (shiftState == 1 ? "shift.fill" : "shift"))
                b.label.text = nil
            case .backspace: b.icon.image = UIImage(systemName: "delete.left"); b.label.text = nil
            case .globe: b.icon.image = UIImage(systemName: "globe"); b.label.text = nil
            case .emoji: b.icon.image = UIImage(systemName: "face.smiling"); b.label.text = nil
            case .ret: b.label.text = s.label; b.label.font = .systemFont(ofSize: 15)
            case .space: b.label.text = s.label; b.label.font = .systemFont(ofSize: 14)
            case .lang, .page: b.label.text = s.label; b.label.font = .systemFont(ofSize: 16, weight: .medium)
            case .char(let c):
                b.label.text = s.label
                let sinhala = Singlish.isSinhala(c)
                b.label.font = .systemFont(ofSize: sinhala ? 21 : (c.count > 1 ? 18 : 23), weight: .regular)
                b.hintLabel.text = s.hint
            case .spacer: break
            }
            b.apply(theme: theme, active: active)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width
        let side: CGFloat = 0
        // rows share whatever height iOS gives us, so every page always fills the keyboard evenly
        if !rows.isEmpty, bounds.height > 0 { rowHeight = bounds.height / CGFloat(rows.count) }
        for (ri, row) in rows.enumerated() {
            let units = row.reduce(CGFloat(0)) { $0 + $1.spec.width }
            // keep standard key width for rows with fewer keys (center them)
            let maxUnits = max(10, units)
            let u = (W - side * 2) / maxUnits
            var x = side + (W - side * 2 - u * units) / 2
            for b in row {
                let w = u * b.spec.width
                b.frame = CGRect(x: x, y: CGFloat(ri) * rowHeight, width: w, height: rowHeight)
                x += w
            }
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(rows.count) * rowHeight) }

    // MARK: touches
    @objc private func down(_ b: KeyButton) {
        stopNameGlow()
        // Fast typing: the next key went down before the last one came up — type the earlier one now,
        // in order, exactly like the system keyboard. Nothing is lost and nothing is swapped.
        if altView == nil, !panning {
            for h in held where h !== b && isTyping(h) && !consumed.contains(ObjectIdentifier(h)) {
                consumed.insert(ObjectIdentifier(h))
                h.animatePress(false)
                h.apply(theme: theme)
                onKey?(h.spec, .up)
            }
        }
        held.removeAll { $0 === b }
        held.append(b)
        b.apply(theme: theme, highlighted: true, active: b.spec.kind == .shift && shiftState > 0)
        b.animatePress(true)
        // no letter pop-up preview — the key itself darkens and shrinks a little instead
        onKey?(b.spec, .down)
    }
    @objc private func up(_ b: KeyButton) {
        hideBubble()
        held.removeAll { $0 === b }
        b.animatePress(false)
        b.apply(theme: theme, active: b.spec.kind == .shift && shiftState > 0)
        scheduleNameGlow()
        if consumed.remove(ObjectIdentifier(b)) != nil { return }   // already typed by the next key press
        onKey?(b.spec, .up)
    }
    @objc private func cancel(_ b: KeyButton) {
        held.removeAll { $0 === b }
        consumed.remove(ObjectIdentifier(b))
        hideBubble()
        b.animatePress(false)
        b.apply(theme: theme, active: b.spec.kind == .shift && shiftState > 0)
        if b.spec.kind == .backspace { onKey?(b.spec, .cursorEnd) }
    }

    private func showBubble(_ b: KeyButton) {
        guard let ov = overlay, bounds.width < 600 else { return }
        let f = b.convert(b.bg.frame, to: ov)
        let l = bubble ?? UILabel()
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 32)
        l.text = b.label.text
        l.backgroundColor = theme.key
        l.textColor = theme.keyText
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.frame = CGRect(x: f.midX - max(f.width, 44) * 0.75, y: max(0, f.minY - 54), width: max(f.width, 44) * 1.5, height: 52)
        if l.frame.minX < 0 { l.frame.origin.x = 2 }
        if l.frame.maxX > ov.bounds.width { l.frame.origin.x = ov.bounds.width - l.frame.width - 2 }
        ov.addSubview(l)
        bubble = l
    }
    private func hideBubble() { bubble?.removeFromSuperview() }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        guard let b = g.view as? KeyButton, let ov = overlay else { return }
        if altView == nil, consumed.contains(ObjectIdentifier(b)) { return }   // already typed by a faster key press
        switch g.state {
        case .began:
            hideBubble()
            altChoices = b.spec.alts
            altIndex = 0
            let st = UIStackView()
            st.axis = .horizontal
            st.distribution = .fillEqually
            st.backgroundColor = theme.key
            st.layer.cornerRadius = 10
            st.layer.shadowColor = UIColor.black.cgColor
            st.layer.shadowOpacity = 0.35
            st.layer.shadowRadius = 6
            for (i, a) in altChoices.enumerated() {
                let l = UILabel()
                l.text = a.display
                l.textAlignment = .center
                l.font = .systemFont(ofSize: 24)
                l.textColor = i == 0 ? .white : theme.keyText
                l.backgroundColor = i == 0 ? theme.accent : .clear
                l.layer.cornerRadius = 8
                l.layer.masksToBounds = true
                st.addArrangedSubview(l)
            }
            let f = b.convert(b.bg.frame, to: ov)
            let cw: CGFloat = 40
            let w = cw * CGFloat(altChoices.count)
            var x = f.midX - cw / 2
            if x + w > ov.bounds.width - 2 { x = ov.bounds.width - w - 2 }
            st.frame = CGRect(x: max(2, x), y: max(0, f.minY - 54), width: w, height: 50)
            ov.addSubview(st)
            altView = st
            onKey?(b.spec, .cursorEnd) // stop repeats if any
        case .changed:
            guard let st = altView else { return }
            let p = g.location(in: st)
            let i = max(0, min(altChoices.count - 1, Int(p.x / 40)))
            if i != altIndex {
                altIndex = i
                for (k, v) in st.arrangedSubviews.enumerated() {
                    (v as? UILabel)?.backgroundColor = k == i ? theme.accent : .clear
                    (v as? UILabel)?.textColor = k == i ? .white : theme.keyText
                }
            }
        case .ended:
            altView?.removeFromSuperview(); altView = nil
            b.apply(theme: theme)
            if altIndex < altChoices.count { onKey?(b.spec, .alt(altChoices[altIndex])) }
        default:
            altView?.removeFromSuperview(); altView = nil
            b.apply(theme: theme)
        }
    }

    private var panLast: CGFloat = 0
    private var panning = false
    @objc private func spacePan(_ g: UIPanGestureRecognizer) {
        guard let b = g.view as? KeyButton else { return }
        let x = g.translation(in: self).x
        switch g.state {
        case .began:
            panLast = 0; panning = true
            b.label.text = "◀  ▶"
        case .changed:
            let step: CGFloat = 9
            let d = Int((x - panLast) / step)
            if d != 0 { panLast += CGFloat(d) * step; onKey?(b.spec, .cursor(d)) }
        default:
            panning = false
            b.label.text = b.spec.label
            b.apply(theme: theme)
            onKey?(b.spec, .cursorEnd)
        }
    }
}

extension KeyboardView: UIGestureRecognizerDelegate {
    /// The space-bar cursor drag starts only after a clear sideways slide, so a quick space tap is never eaten.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, pan.view is KeyButton else { return super.gestureRecognizerShouldBegin(g) }
        let t = pan.translation(in: self)
        return abs(t.x) > 12 && abs(t.x) > abs(t.y) * 1.5
    }
}

// MARK: - "SHEHAN" idle glow
/// When nobody is typing, the S-H-E-H-A-N keys light up one after another so the name can be read.
/// It only changes key colours; the first touch stops it instantly and restores the keys, so typing is never affected.
extension KeyboardView {
    private static let glowName = Array("shehan")
    private var glow: (timer: Timer?, step: Int, cycles: Int, lit: KeyButton?) {
        get { glowState }
        set { glowState = newValue }
    }

    func scheduleNameGlow(after delay: TimeInterval = 3.5) {
        glow.timer?.invalidate()
        guard nameGlowEnabled else { return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.glowStep() }
        RunLoop.main.add(t, forMode: .common)
        glow = (t, 0, 0, nil)
    }

    func stopNameGlow() {
        let g = glow
        g.timer?.invalidate()
        if let b = g.lit { b.layer.removeAllAnimations(); b.bg.layer.removeAllAnimations(); b.apply(theme: theme, active: b.spec.kind == .shift && shiftState > 0) }
        glow = (nil, 0, 0, nil)
    }

    private func key(for letter: Character) -> KeyButton? {
        for b in rows.flatMap({ $0 }) where !b.isHidden {
            if case .char(let c) = b.spec.kind, c.count == 1, c.lowercased() == String(letter) { return b }
        }
        return nil
    }

    private func glowStep() {
        guard nameGlowEnabled, window != nil, !isHidden, held.isEmpty else { stopNameGlow(); return }
        var g = glow
        if let prev = g.lit {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                prev.apply(theme: self.theme)
            }
            g.lit = nil
        }
        let names = KeyboardView.glowName
        guard g.step < names.count, let b = key(for: names[g.step]) else {
            // whole name shown (or this page has no such letters) — rest, then again a few times
            g.cycles += 1
            g.step = 0
            let again = g.cycles < 6 && key(for: "s") != nil
            g.timer = again ? Timer(timeInterval: 1.6, repeats: false) { [weak self] _ in self?.glowStep() } : nil
            if let t = g.timer { RunLoop.main.add(t, forMode: .common) }
            glow = g
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            b.bg.backgroundColor = self.theme.accent
            b.label.textColor = .white
        }
        g.lit = b
        g.step += 1
        let t = Timer(timeInterval: 0.42, repeats: false) { [weak self] _ in self?.glowStep() }
        RunLoop.main.add(t, forMode: .common)
        g.timer = t
        glow = g
    }
}
