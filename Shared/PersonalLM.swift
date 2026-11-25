import Foundation

/// A small personal language model that learns from everything you type — the same objective an LLM is trained
/// on ("predict the next token"), learned by counting instead of gradient descent, so it trains instantly on the
/// phone and predicts in microseconds.
///
/// • Word model: interpolated Kneser-Ney, up to 4-grams (uses the last 3 words) → next-word prediction and
///   context-aware ranking of suggestions.
/// • Character model: up to 5-grams over the letters you press → predicts your next letter; the keyboard uses it to
///   resolve taps that land between two keys (like Gboard / iOS "dynamic key targets").
struct PersonalLM: Codable {
    struct Ctx: Codable {
        var n: [String: Int] = [:]   // next token → count
        var total = 0
    }
    static let order = 3          // words of context (4-gram model)
    static let charOrder = 4      // characters of context (5-gram model)
    static let discount = 0.75

    var words: [String: Ctx] = [:]          // context key → next-word counts ("" = unigram)
    var cont: [String: Int] = [:]           // Kneser-Ney continuation count: in how many different contexts a word appeared
    var contTotal = 0
    var chars: [String: [String: Int]] = [:] // previous chars → next char counts

    static func key(_ ctx: ArraySlice<String>) -> String { ctx.joined(separator: "\u{1F}") }

    // MARK: training
    mutating func observe(_ w: String, context: [String]) {
        let ctx = context.suffix(PersonalLM.order)
        for k in 0...ctx.count {
            let key = PersonalLM.key(ctx.suffix(k))
            var c = words[key] ?? Ctx()
            if k == 1, c.n[w] == nil { cont[w, default: 0] += 1; contTotal += 1 }
            c.n[w, default: 0] += 1
            c.total += 1
            words[key] = c
        }
        if words.count > 60_000 { prune() }
    }

    /// Adds already counted pairs (migration from the older bigram store).
    mutating func seedPair(_ p: String, _ w: String, _ count: Int) {
        for key in [PersonalLM.key([p][...]), ""] {
            var c = words[key] ?? Ctx()
            if key != "", c.n[w] == nil { cont[w, default: 0] += 1; contTotal += 1 }
            c.n[w, default: 0] += count
            c.total += count
            words[key] = c
        }
    }

    mutating func observeChars(_ letters: String) {
        let t = ["^"] + letters.lowercased().map { String($0) } + ["$"]
        for i in 1..<t.count {
            for k in 0...min(PersonalLM.charOrder, i) {
                let ctx = t[(i - k)..<i].joined()
                chars[ctx, default: [:]][t[i], default: 0] += 1
            }
        }
        if chars.count > 40_000 { chars = chars.filter { $0.key.count <= 2 || $0.value.values.reduce(0, +) > 1 } }
    }

    mutating func forget(_ w: String) {
        for k in words.keys where words[k]?.n[w] != nil {
            let c = words[k]!.n[w]!
            words[k]!.n.removeValue(forKey: w)
            words[k]!.total -= c
        }
        if let c = cont.removeValue(forKey: w) { contTotal -= c }
    }

    private mutating func prune() {
        // drop rare long contexts first (seen once), keep everything short and everything you use often
        words = words.filter { $0.key.isEmpty || $0.value.total > 1 || !$0.key.contains("\u{1F}") }
        if words.count > 50_000 { words = words.filter { $0.key.filter { $0 == "\u{1F}" }.count < 2 || $0.value.total > 2 } }
    }

    // MARK: prediction
    /// P(w | context) with interpolated Kneser-Ney smoothing.
    func p(_ w: String, _ context: [String]) -> Double { scorer(context)(w) }

    /// Looks the context up once, then scores many candidate words quickly.
    func scorer(_ context: [String]) -> (String) -> Double {
        var ctx = Array(context.suffix(PersonalLM.order))
        var chain: [Ctx] = []
        while !ctx.isEmpty {
            if let c = words[PersonalLM.key(ctx[...])], c.total > 0 { chain.append(c) }
            ctx.removeFirst()
        }
        let cont = self.cont
        let denom = Double(contTotal) + 0.2 * Double(cont.count + 20_000)
        return { w in
            // lowest order: continuation probability, smoothed toward uniform so new words are never zero
            var prob = (Double(cont[w] ?? 0) + 0.2) / denom
            for c in chain.reversed() {
                let cw = Double(c.n[w] ?? 0), tot = Double(c.total)
                prob = max(cw - PersonalLM.discount, 0) / tot + PersonalLM.discount * Double(c.n.count) / tot * prob
            }
            return prob
        }
    }

    /// Most likely next words after `context`.
    func predict(_ context: [String], k: Int = 3, filter: ((String) -> Bool)? = nil) -> [(String, Double)] {
        var cand = Set<String>()
        var ctx = Array(context.suffix(PersonalLM.order))
        while !ctx.isEmpty {
            if let c = words[PersonalLM.key(ctx[...])] { for w in c.n.keys { cand.insert(w) } }
            if cand.count > 200 { break }
            ctx.removeFirst()
        }
        if cand.isEmpty, context.isEmpty, let u = words[""] { for (w, _) in u.n.sorted(by: { $0.value > $1.value }).prefix(30) { cand.insert(w) } }
        let score = scorer(context)
        return cand.filter { filter?($0) ?? true }.map { ($0, score($0)) }.sorted { $0.1 > $1.1 }.prefix(k).map { $0 }
    }

    /// Probability of the next character (lower-case letter, or "$" = end of word) after `prefix`
    /// (`^` + the letters of the current word). Stupid back-off — fast enough to run on every touch.
    func pChar(_ next: String, after prefix: String) -> Double {
        let p = Array(prefix.lowercased())
        var weight = 1.0
        for k in stride(from: min(PersonalLM.charOrder, p.count), through: 0, by: -1) {
            let ctx = String(p.suffix(k))
            if let m = chars[ctx] {
                let tot = m.values.reduce(0, +)
                if tot > 0, let c = m[next] { return weight * Double(c) / Double(tot) }
            }
            weight *= 0.4
        }
        return weight / 30
    }

    var isEmpty: Bool { words.isEmpty && chars.isEmpty }
    var stats: (contexts: Int, vocabulary: Int, charContexts: Int) { (words.count, words[""]?.n.count ?? 0, chars.count) }
}
