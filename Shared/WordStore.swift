import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Word suggestions, learning (unigrams + next-word bigrams) and English spell checking.
final class WordStore {
    static let shared = WordStore()

    struct Model: Codable {
        var words: [String: Int] = [:]        // learned word → count
        var bigrams: [String: [String: Int]] = [:] // previous word → next word → count
        var romanOf: [String: String] = [:]   // learned Sinhala word → the roman the user typed
    }

    private(set) var data = Model()
    private var siBuiltin: [(word: String, skel: String)] = []
    private var dirty = false
    private var skelCache: [String: String] = [:]
    private func skeleton(_ w: String) -> String {
        if let s = skelCache[w] { return s }
        let s = Singlish.sinhalaSkeleton(w)
        skelCache[w] = s
        return s
    }
    private let url = SharedStore.shared.fileURL("words.json")
    private let q = DispatchQueue(label: "wordstore")

    private init() {
        if let d = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Model.self, from: d) { data = decoded }
        let bundles = [Bundle.main, Bundle(for: WordStore.self)]
        for b in bundles {
            if let u = b.url(forResource: "words_si", withExtension: "txt"), let text = try? String(contentsOf: u, encoding: .utf8) {
                siBuiltin = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { (word: $0, skel: Singlish.sinhalaSkeleton($0)) }
                break
            }
        }
    }

    // MARK: learning
    func learn(_ word: String, roman: String? = nil, previous: String?) {
        guard SharedStore.shared[bool: SharedStore.K.learnWords] else { return }
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard w.count >= 2, w.count <= 40 else { return }
        data.words[w, default: 0] += 1
        if let r = roman, Singlish.isSinhala(w) { data.romanOf[w] = r }
        if let p = previous?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)), !p.isEmpty {
            data.bigrams[p, default: [:]][w, default: 0] += 1
        }
        if data.words.count > 8000 { prune() }
        dirty = true
        scheduleSave()
    }

    func forget(_ word: String) {
        data.words.removeValue(forKey: word); data.romanOf.removeValue(forKey: word); data.bigrams.removeValue(forKey: word)
        for k in data.bigrams.keys { data.bigrams[k]?.removeValue(forKey: word) }
        dirty = true; save()
    }
    func forgetAll() { data = Model(); dirty = true; save() }

    private func prune() {
        let keep = data.words.sorted { $0.value > $1.value }.prefix(6000)
        data.words = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        data.bigrams = data.bigrams.filter { data.words[$0.key] != nil }
    }

    private var saveWork: DispatchWorkItem?
    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }
    func save() {
        guard dirty else { return }
        dirty = false
        let snapshot = data
        q.async { [url] in
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
        }
    }

    // MARK: suggestions
    /// Sinhala suggestions for a roman word being typed. First item is the direct conversion.
    func sinhalaSuggestions(roman: String, max: Int = 6) -> [String] {
        guard !roman.isEmpty else { return [] }
        let direct = Singlish.convert(roman)
        var out = [direct]
        var seen: Set<String> = [direct]
        let skel = Singlish.romanSkeleton(roman)
        let variants = Singlish.variants(roman)

        var scored: [(String, Double)] = []
        // learned words: typed with exactly this roman before → strongest
        for (w, r) in data.romanOf where r.lowercased().hasPrefix(roman.lowercased()) {
            scored.append((w, 1000 + Double(data.words[w] ?? 1) - Double(r.count - roman.count)))
        }
        // learned + builtin words by fuzzy skeleton prefix
        for (w, c) in data.words where Singlish.isSinhala(w) {
            let ws = skeleton(w)
            if ws == skel { scored.append((w, 500 + Double(c))) } else if ws.hasPrefix(skel) { scored.append((w, 200 + Double(c) - Double(ws.count - skel.count))) }
        }
        for (w, ws) in siBuiltin {
            if ws == skel { scored.append((w, 300)) } else if skel.count >= 2, ws.hasPrefix(skel) { scored.append((w, 100 - Double(ws.count - skel.count))) }
        }
        // spelling variants that are real words
        let known = Set(siBuiltin.map { $0.word }).union(data.words.keys)
        for v in variants where known.contains(v) { scored.append((v, 400)) }

        for (w, _) in scored.sorted(by: { $0.1 > $1.1 }) where !seen.contains(w) {
            seen.insert(w); out.append(w)
            if out.count >= max { return out }
        }
        for v in variants where !seen.contains(v) {
            seen.insert(v); out.append(v)
            if out.count >= max { break }
        }
        return out
    }

    /// English completions + corrections for a partial word.
    func englishSuggestions(partial: String, max: Int = 3) -> (list: [String], correction: String?) {
        guard !partial.isEmpty else { return ([], nil) }
        var out: [String] = []
        var correction: String?
        let lower = partial.lowercased()
        // learned words first
        for (w, _) in data.words.filter({ !Singlish.isSinhala($0.key) && $0.key.lowercased().hasPrefix(lower) && $0.key.count > partial.count }).sorted(by: { $0.value > $1.value }).prefix(2) {
            out.append(matchCase(w, partial))
        }
        #if canImport(UIKit)
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (partial as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: partial, range: range, startingAt: 0, wrap: false, language: "en_US")
        if miss.location != NSNotFound, data.words[partial] == nil, data.words[lower] == nil {
            if let g = checker.guesses(forWordRange: range, in: partial, language: "en_US"), let first = g.first {
                correction = matchCase(first, partial)
                for x in g.prefix(2) where !out.contains(x) { out.append(matchCase(x, partial)) }
            }
        }
        if let comps = checker.completions(forPartialWordRange: range, in: partial, language: "en_US") {
            for c in comps.prefix(4) where !out.contains(c) && c.count > partial.count { out.append(matchCase(c, partial)) }
        }
        #endif
        return (Array(out.prefix(max)), correction)
    }

    func nextWords(after previous: String, max: Int = 3) -> [String] {
        let p = previous.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let m = data.bigrams[p] ?? data.bigrams[p.lowercased()] else { return [] }
        return m.sorted { $0.value > $1.value }.prefix(max).map { $0.key }
    }

    private func matchCase(_ w: String, _ typed: String) -> String {
        guard let f = typed.first else { return w }
        if typed.count > 1, typed == typed.uppercased() { return w.uppercased() }
        if f.isUppercase { return w.prefix(1).uppercased() + w.dropFirst() }
        return w
    }

    var learnedList: [(String, Int)] { data.words.sorted { $0.value > $1.value }.map { ($0.key, $0.value) } }
}
