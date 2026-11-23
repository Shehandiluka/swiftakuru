import UIKit

/// Remembers recently copied text (needs "Allow Full Access").
final class ClipboardStore {
    static let shared = ClipboardStore()
    struct Item: Codable, Equatable { var text: String; var pinned: Bool; var date: Date }
    private(set) var items: [Item] = []
    private var lastChange: Int
    private let url = SharedStore.shared.fileURL("clipboard.json")

    private init() {
        lastChange = SharedStore.shared.defaults.integer(forKey: "clipLastChange")
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode([Item].self, from: d) { items = v }
    }

    /// Reads the system clipboard only when it changed (changeCount does not trigger the paste banner).
    @discardableResult
    func capture() -> Bool {
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChange else { return false }
        lastChange = pb.changeCount
        SharedStore.shared.defaults.set(lastChange, forKey: "clipLastChange")
        guard pb.hasStrings, let s = pb.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.count < 20000 else { return false }
        add(s)
        return true
    }

    func add(_ s: String) {
        if let i = items.firstIndex(where: { $0.text == s }) {
            let pinned = items[i].pinned
            items.remove(at: i)
            items.insert(Item(text: s, pinned: pinned, date: Date()), at: 0)
        } else {
            items.insert(Item(text: s, pinned: false, date: Date()), at: 0)
        }
        trim(); save()
    }
    func remove(_ text: String) { items.removeAll { $0.text == text }; save() }
    func togglePin(_ text: String) { if let i = items.firstIndex(where: { $0.text == text }) { items[i].pinned.toggle(); save() } }
    func clearUnpinned() { items.removeAll { !$0.pinned }; save() }

    /// pinned first, then newest
    var sorted: [Item] { items.filter { $0.pinned } + items.filter { !$0.pinned } }

    private func trim() {
        let maxN = SharedStore.shared.clipboardMax
        var unpinned = 0
        items = items.filter { it in
            if it.pinned { return true }
            unpinned += 1
            return unpinned <= maxN
        }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: url, options: [.atomic]) }
    }
}
