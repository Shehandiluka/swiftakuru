import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Word suggestions, learning (unigrams + next-word bigrams) and English spell checking.
final class WordStore {
    static let shared = WordStore()

    /// Everything learned on this phone. Nothing leaves the device.
    struct Model: Codable {
        var words: [String: Int] = [:]               // word → times used
        var bigrams: [String: [String: Int]] = [:]   // previous word → next word → count
        var romanOf: [String: String] = [:]          // Sinhala word → roman the user typed last
        var picks: [String: [String: Int]] = [:]     // roman typed → Sinhala word chosen → strength
        var lastDay: [String: Int] = [:]             // word → day it was last used (recency)
        var trigrams: [String: [String: Int]] = [:]  // "w1 w2" → next word → count
        var lm = PersonalLM()                         // personal language model (next word / next letter)

        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            words = try c.decodeIfPresent([String: Int].self, forKey: .words) ?? [:]
            bigrams = try c.decodeIfPresent([String: [String: Int]].self, forKey: .bigrams) ?? [:]
            romanOf = try c.decodeIfPresent([String: String].self, forKey: .romanOf) ?? [:]
            picks = try c.decodeIfPresent([String: [String: Int]].self, forKey: .picks) ?? [:]
            lastDay = try c.decodeIfPresent([String: Int].self, forKey: .lastDay) ?? [:]
            trigrams = try c.decodeIfPresent([String: [String: Int]].self, forKey: .trigrams) ?? [:]
            lm = try c.decodeIfPresent(PersonalLM.self, forKey: .lm) ?? PersonalLM()
            // older versions kept only word pairs: move them into the language model once
            if lm.isEmpty, !bigrams.isEmpty {
                for (p, m) in bigrams { for (w, n) in m { lm.seedPair(p, w, n) } }
            }
            bigrams = [:]; trigrams = [:]
        }
    }

    private(set) var data = Model()
    /// Built-in Sinhala words sorted by skeleton, for fast prefix lookups (binary search).
    private var builtin: [(skel: String, word: String)] = []
    private var builtinSet: Set<String> = []
    private var dirty = false
    private var skelCache: [String: String] = [:]
    private func skeleton(_ w: String) -> String {
        if let s = skelCache[w] { return s }
        let s = Singlish.sinhalaSkeleton(w)
        if skelCache.count > 20000 { skelCache.removeAll(keepingCapacity: true) }
        skelCache[w] = s
        return s
    }
    private let url = SharedStore.shared.fileURL("words.json")
    private let q = DispatchQueue(label: "wordstore")
    /// The last words you wrote (context for the language model while learning).
    private var history: [String] = []
    private static var today: Int { Int(Date().timeIntervalSince1970 / 86400) }

    private var loadedAt: Date?
    private func fileDate() -> Date? { (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date }
    /// The app may have taught new words while the keyboard was closed — pick them up (cheap date check).
    func reloadIfChanged() {
        guard loaded, !dirty, let d = fileDate(), d != loadedAt else { return }
        q.async { [url] in
            guard let raw = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(Model.self, from: raw) else { return }
            DispatchQueue.main.async { if !self.dirty { self.data = m; self.loadedAt = d } }
        }
    }

    /// false for a moment after the keyboard starts: everything is read in the background so the keys appear at once.
    private(set) var loaded = false

    private init() {
        q.async { [url] in
            var model = Model()
            if let d = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Model.self, from: d) { model = decoded }
            var bi: [(skel: String, word: String)] = [], set: Set<String> = []
            for b in [Bundle.main, Bundle(for: WordStore.self)] {
                if let u = b.url(forResource: "words_si", withExtension: "txt"), let text = try? String(contentsOf: u, encoding: .utf8) {
                    let list = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    bi = list.map { (skel: Singlish.sinhalaSkeleton($0), word: $0) }.sorted { $0.skel < $1.skel }
                    set = Set(list)
                    break
                }
            }
            let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            DispatchQueue.main.async {
                self.data = model
                self.builtin = bi
                self.builtinSet = set
                self.loadedAt = date
                self.loaded = true
            }
        }
    }

    /// Tests: wait for the background load.
    func waitUntilLoaded() {
        q.sync {}
        let until = Date().addingTimeInterval(2)
        while !loaded && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    static func clean(_ w: String) -> String { w.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)) }

    // MARK: learning
    /// Called for every word you finish. `chosen` = you tapped this suggestion instead of the first one
    /// (a strong signal); `rejected` = the suggestion you skipped (it is ranked lower for that spelling next time).
    func learn(_ word: String, roman: String? = nil, previous: String?, chosen: Bool = false, rejected: String? = nil) {
        guard loaded, SharedStore.shared[bool: SharedStore.K.learnWords] else { return }
        let w = WordStore.clean(word)
        guard w.count >= 1, w.count <= 40 else { return }
        data.words[w, default: 0] += chosen ? 3 : 1
        data.lastDay[w] = WordStore.today
        if let r = roman?.lowercased(), !r.isEmpty, Singlish.isSinhala(w) {
            data.romanOf[w] = r
            data.picks[r, default: [:]][w, default: 0] += chosen ? 4 : 1
            if let rj = rejected, rj != w, let v = data.picks[r]?[rj] { data.picks[r]?[rj] = max(0, v - 2) }
        }
        // language model: learn "after these words comes this word"
        let p = previous.map(WordStore.clean) ?? ""
        if p.isEmpty { history = [] } else if history.last != p { history = [p] }
        data.lm.observe(w, context: history)
        history.append(w)
        if history.count > PersonalLM.order { history.removeFirst() }
        if let last = word.trimmingCharacters(in: .whitespaces).last, ".?!।".contains(last) { history = [] }
        // letter model: learn the keys you press, in order
        if let r = roman, !r.isEmpty { data.lm.observeChars(r) } else if !Singlish.isSinhala(w), w.count <= 20 { data.lm.observeChars(w) }
        if data.words.count > 9000 { prune() }
        dirty = true
        scheduleSave()
    }

    /// "Train" from your own text (old chats, notes): learns words and which word follows which.
    @discardableResult
    func learn(fromText text: String) -> Int {
        var n = 0
        for line in text.components(separatedBy: .newlines) {
            var prev: String?
            history = []
            for raw in line.split(whereSeparator: { $0.isWhitespace }) {
                let w = WordStore.clean(String(raw))
                guard w.count >= 1, w.count <= 40, !w.allSatisfy({ $0.isNumber }) else { prev = nil; continue }
                learn(w, previous: prev)
                prev = w; n += 1
            }
        }
        save()
        return n
    }

    func forget(_ word: String) {
        data.lm.forget(word)
        data.words.removeValue(forKey: word); data.romanOf.removeValue(forKey: word); data.bigrams.removeValue(forKey: word); data.lastDay.removeValue(forKey: word)
        for k in data.bigrams.keys { data.bigrams[k]?.removeValue(forKey: word) }
        for k in data.picks.keys { data.picks[k]?.removeValue(forKey: word) }
        for k in data.trigrams.keys { data.trigrams[k]?.removeValue(forKey: word) }
        dirty = true; save()
    }
    func forgetAll() { data = Model(); dirty = true; save() }

    private func prune() {
        // keep what you use often or used recently
        let t = WordStore.today
        let scored = data.words.map { ($0.key, Double($0.value) + 30.0 / Double(max(1, t - (data.lastDay[$0.key] ?? 0)))) }
        let keep = Set(scored.sorted { $0.1 > $1.1 }.prefix(7000).map { $0.0 })
        data.words = data.words.filter { keep.contains($0.key) }
        data.lastDay = data.lastDay.filter { keep.contains($0.key) }
        data.romanOf = data.romanOf.filter { keep.contains($0.key) }
        data.bigrams = data.bigrams.filter { keep.contains($0.key) }
        if data.trigrams.count > 6000 { data.trigrams = Dictionary(uniqueKeysWithValues: data.trigrams.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(4000).map { ($0.key, $0.value) }) }
        if data.picks.count > 6000 { data.picks = Dictionary(uniqueKeysWithValues: data.picks.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(4000).map { ($0.key, $0.value) }) }
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
        q.async { [url, weak self] in
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
            let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            DispatchQueue.main.async { self?.loadedAt = date }
        }
    }

    var stats: (words: Int, pairs: Int, spellings: Int) {
        (data.words.count, data.lm.stats.contexts, data.picks.count)
    }

    /// Next-letter probability for the keys (0 until the model is loaded → touches are left alone).
    func pNextChar(_ c: String, prefix: String) -> Double {
        loaded ? data.lm.pChar(c, after: prefix) : 0
    }

    /// Language-model score of a word in this context, 0 (unlikely) … ~8 (very likely).
    private func lmScore(_ w: String, _ context: [String]) -> Double {
        max(0, log2(data.lm.p(w, context)) + 16) * 0.5
    }

    // MARK: suggestions
    /// Sinhala suggestions for a roman word being typed, best first.
    /// Three things are mixed into one score: (1) what YOU chose for this spelling before,
    /// (2) the words around it (what you usually write after the previous word),
    /// (3) the dictionary + your vocabulary (spelling match, how often and how recently used).
    /// `primary` is the word space will type: the direct conversion, unless you have clearly taught a better one.
    func sinhalaSuggestions(roman: String, context: [String] = [], max: Int = 3) -> (list: [String], primary: Int) {
        guard !roman.isEmpty else { return ([], -1) }
        let r = roman.lowercased()
        let direct = Singlish.convert(roman)
        let skel = Singlish.romanSkeleton(roman)
        let context = context.map(WordStore.clean).filter { !$0.isEmpty }
        let lmP = data.lm.scorer(context)
        let t = WordStore.today
        var score: [String: Double] = [:]

        func base(_ w: String) -> Double {
            var s = 0.0
            s += max(0, log2(lmP(w)) + 16) * 0.5   // how likely this word is here (frequency + the words before it)
            if let d = data.lastDay[w] { s += t - d <= 1 ? 1.0 : (t - d <= 7 ? 0.5 : 0) }
            if builtinSet.contains(w) { s += 0.6 }
            return s
        }
        func add(_ w: String, _ s: Double) { score[w] = Swift.max(score[w] ?? -.infinity, s + base(w)) }

        // the direct conversion always takes part
        add(direct, 3.0)
        // (1) your own choices for exactly this spelling
        if let ch = data.picks[r] { for (w, n) in ch where n > 0 { add(w, 3.0 + 2.5 * log2(1 + Double(n))) } }
        // ...and for spellings that start like this one (you are still typing)
        if r.count >= 2 {
            for (w, rr) in data.romanOf where rr.count > r.count && rr.hasPrefix(r) { add(w, 2.2 - 0.25 * Double(rr.count - r.count)) }
        }
        // (2) words that usually come next (only if they fit what you are typing)
        do {
            for (w, _) in data.lm.predict(context, k: 60, filter: Singlish.isSinhala) {
                let ws = skeleton(w)
                if ws == skel { add(w, 2.0) } else if skel.count >= 2, ws.hasPrefix(skel) { add(w, 1.0 - 0.15 * Double(ws.count - skel.count)) }
            }
        }
        // (3) your vocabulary + the dictionary by sound
        if skel.count >= 1 {
            var checked = 0
            for (w, _) in data.words where Singlish.isSinhala(w) {
                checked += 1; if checked > 4000 { break }
                let ws = skeleton(w)
                if ws == skel { add(w, 2.0) } else if skel.count >= 2, ws.hasPrefix(skel) { add(w, 0.8 - 0.15 * Double(ws.count - skel.count)) }
            }
            var i = lowerBound(skel), seen = 0
            while i < builtin.count, seen < 120, builtin[i].skel.hasPrefix(skel) {
                let e = builtin[i]
                add(e.word, e.skel == skel ? 1.6 : 0.5 - 0.12 * Double(e.skel.count - skel.count))
                i += 1; seen += 1
            }
        }
        // spelling variants that are real words
        for v in Singlish.variants(roman, limit: 12) where builtinSet.contains(v) || data.words[v] != nil { add(v, 1.8) }

        let ranked = score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.count < $1.key.count }.map { $0.key }
        // space types the top word only when you have taught it (picked it for this spelling twice or more)
        let top = ranked.first ?? direct
        let taught = (data.picks[r]?[top] ?? 0) >= 2 && (score[top] ?? 0) >= (score[direct] ?? 0) + 1.5
        let first = taught ? top : direct
        var out = [first]
        for w in ranked where w != first { out.append(w); if out.count >= max { break } }
        return (out, 0)
    }

    private func lowerBound(_ key: String) -> Int {
        var lo = 0, hi = builtin.count
        while lo < hi { let m = (lo + hi) / 2; if builtin[m].skel < key { lo = m + 1 } else { hi = m } }
        return lo
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

    /// Next-word predictions from the personal language model.
    func nextWords(context: [String], max: Int = 3) -> [String] {
        guard loaded else { return [] }
        let ctx = context.map(WordStore.clean).filter { !$0.isEmpty }
        guard !ctx.isEmpty else { return [] }
        return data.lm.predict(ctx, k: max).filter { $0.1 > 0.02 }.map { $0.0 }
    }

    /// Re-orders English completions by how likely they are in this context (corrections keep their place).
    func rankByContext(_ list: [String], context: [String]) -> [String] {
        guard loaded, list.count > 1 else { return list }
        let ctx = context.map(WordStore.clean).filter { !$0.isEmpty }
        let lmP = data.lm.scorer(ctx)
        func sc(_ w: String) -> Double { max(0, log2(lmP(w.lowercased())) + 16) * 0.5 }
        return list.enumerated().sorted { a, b in
            let sa = sc(a.element) - Double(a.offset) * 0.8
            let sb = sc(b.element) - Double(b.offset) * 0.8
            return sa > sb
        }.map { $0.element }
    }

    private func matchCase(_ w: String, _ typed: String) -> String {
        guard let f = typed.first else { return w }
        if typed.count > 1, typed == typed.uppercased() { return w.uppercased() }
        if f.isUppercase { return w.prefix(1).uppercased() + w.dropFirst() }
        return w
    }

    var learnedList: [(String, Int)] { data.words.sorted { $0.value > $1.value }.map { ($0.key, $0.value) } }
}
