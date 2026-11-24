import UIKit

protocol ThemedPanel: AnyObject { func applyTheme(_ t: KBTheme) }

/// The strip above the keys: suggestions, or a toolbar, or a panel title with a back button.
final class SuggestionBar: UIView {
    var theme = KBTheme.named("swift") { didSet { backgroundColor = theme.id == "photo" ? theme.bar : .clear } }
    var onPick: ((String) -> Void)?
    var onTool: ((String) -> Void)?
    var lastEmoji: [String] = []
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var items: [String] = []
    private var backAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.spacing = 2
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 4), scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func clear() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        scroll.contentOffset = .zero
    }

    func showSuggestions(_ all: [String], primary: Int) {
        // at most 3 suggestions; the highlighted one is always kept
        var list = Array(all.prefix(3)), primary = primary
        if primary >= 3, all.indices.contains(primary) {
            list = [all[primary]] + all.enumerated().filter { $0.offset != primary }.map { $0.element }.prefix(2)
            primary = 0
        }
        clear()
        items = list
        stack.distribution = .fillEqually
        for (i, s) in list.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(s, for: .normal)
            b.titleLabel?.font = Singlish.isSinhala(s) ? .systemFont(ofSize: 19, weight: i == 0 ? .semibold : .regular) : .systemFont(ofSize: 17, weight: i == primary ? .semibold : .regular)
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.setTitleColor(i == primary ? .white : theme.specialText, for: .normal)
            b.backgroundColor = i == primary ? theme.accent : (i == 0 && Singlish.isSinhala(s) ? theme.key.withAlphaComponent(0.55) : .clear)
            b.layer.cornerRadius = 8
            b.tag = i
            b.addTarget(self, action: #selector(tapItem(_:)), for: .touchUpInside)
            let minW = b.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
            minW.priority = UILayoutPriority(999)
            minW.isActive = true
            stack.addArrangedSubview(b)
        }
    }

    @objc private func tapItem(_ b: UIButton) {
        guard items.indices.contains(b.tag) else { return }
        onPick?(items[b.tag])
    }

    func showToolbar(clipboard: Bool, update: Bool = false, secret: Bool = false) {
        clear()
        items = []
        stack.distribution = .fillEqually
        let tools: [(String, String?, String)] = [
            ("emoji", "face.smiling", ""), ("clipboard", clipboard ? "doc.on.clipboard.fill" : "doc.on.clipboard", ""), ("ai", "sparkles", ""),
            ("translate", "character.bubble", ""),
            ("sinhala", nil, "අ"), ("settings", update ? "arrow.down.circle.fill" : "gearshape", ""), ("hide", "keyboard.chevron.compact.down", ""),
        ].flatMap { t -> [(String, String?, String)] in t.0 == "settings" && secret ? [("secret", "lock", ""), t] : [t] }
        for (id, sym, text) in tools {
            let b = UIButton(type: .system)
            if let s = sym { b.setImage(UIImage(systemName: s, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal) } else {
                b.setTitle(text, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
            }
            b.tintColor = (id == "settings" && update) ? UIColor.systemOrange : ((id == "ai" || (id == "translate" && ClipboardStore.shared.pending)) ? theme.accent : theme.specialText)
            b.setTitleColor(theme.specialText, for: .normal)
            b.accessibilityIdentifier = id
            b.accessibilityLabel = id
            b.addTarget(self, action: #selector(tapTool(_:)), for: .touchUpInside)
            stack.addArrangedSubview(b)
        }
    }

    @objc private func tapTool(_ b: UIButton) { if let id = b.accessibilityIdentifier { onTool?(id) } }

    func showTitle(_ title: String, back: @escaping () -> Void) {
        clear()
        items = []
        backAction = back
        stack.distribution = .fill
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.setTitle("  ABC", for: .normal)
        b.tintColor = theme.specialText
        b.setTitleColor(theme.specialText, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let l = UILabel()
        l.text = title
        l.textColor = theme.specialText
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textAlignment = .center
        let spacer = UIView()
        spacer.widthAnchor.constraint(equalToConstant: 90).isActive = true
        stack.addArrangedSubview(b); stack.addArrangedSubview(l); stack.addArrangedSubview(spacer)
    }
    @objc private func tapBack() { backAction?() }
}
