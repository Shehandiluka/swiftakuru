import Foundation

/// The built-in Sinhala dictionary + word-pair model (built from public corpora by tools/lexicon).
/// Files are memory-mapped and binary-searched in place, so ~80,000 words and ~90,000 word pairs cost almost no
/// memory in the keyboard and load in a few milliseconds.
///   si_lex.tsv      skeleton \t word \t count   (sorted by skeleton bytes)  → "what words sound like this?"
///   si_words.tsv    word \t count               (sorted by word bytes)      → "how common is this word?" + prefix completion
///   si_bigrams.tsv  w1 \t w2 \t count           (sorted by w1\tw2 bytes)    → "what usually comes after w1?"
final class BaseLexicon {
    static let shared = BaseLexicon()

    private final class Table {
        let data: Data
        let lines: [Int32]   // start offset of every line
        init?(_ name: String) {
            var url: URL?
            for b in [Bundle.main, Bundle(for: BaseLexicon.self)] { if let u = b.url(forResource: name, withExtension: "tsv") { url = u; break } }
            guard let u = url, let d = try? Data(contentsOf: u, options: .alwaysMapped), !d.isEmpty else { return nil }
            data = d
            var starts: [Int32] = [0]
            starts.reserveCapacity(100_000)
            d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                let b = p.bindMemory(to: UInt8.self)
                for i in 0..<(b.count - 1) where b[i] == 10 { starts.append(Int32(i + 1)) }
            }
            lines = starts
        }
        var count: Int { lines.count }

        /// fields of line i (split on tab)
        func fields(_ i: Int) -> [String] {
            let start = Int(lines[i]), end = i + 1 < lines.count ? Int(lines[i + 1]) - 1 : data.count
            guard end > start, let s = String(data: data.subdata(in: start..<end), encoding: .utf8) else { return [] }
            return s.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }

        /// compares the start of line i with `key` bytes; 0 = line starts with key
        private func compare(_ i: Int, _ key: [UInt8]) -> Int {
            let start = Int(lines[i])
            return data.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> Int in
                let b = p.bindMemory(to: UInt8.self)
                var j = 0
                while j < key.count {
                    let pos = start + j
                    let c: Int = pos < b.count ? Int(b[pos]) : -1
                    if c == 10 || c < 0 { return -1 }          // line shorter than key → line < key
                    if c != Int(key[j]) { return c < Int(key[j]) ? -1 : 1 }
                    j += 1
                }
                return 0
            }
        }

        /// first line whose beginning is >= key
        func lowerBound(_ key: [UInt8]) -> Int {
            var lo = 0, hi = lines.count
            while lo < hi { let m = (lo + hi) / 2; if compare(m, key) < 0 { lo = m + 1 } else { hi = m } }
            return lo
        }
        /// lines that start with key (at most `limit`)
        func prefixed(_ key: [UInt8], limit: Int) -> [Int] {
            var i = lowerBound(key), out: [Int] = []
            while i < lines.count, out.count < limit, compare(i, key) == 0 { out.append(i); i += 1 }
            return out
        }
    }

    private var lex: Table?, words: Table?, bigrams: Table?
    private(set) var loaded = false
    private var freqCache: [String: Int] = [:]

    private init() {}

    /// Call once from a background queue.
    func load() {
        guard !loaded else { return }
        let l = Table("si_lex"), w = Table("si_words"), b = Table("si_bigrams")
        DispatchQueue.main.async { self.lex = l; self.words = w; self.bigrams = b; self.loaded = true }
    }

    var wordCount: Int { words?.count ?? 0 }

    /// Words whose sound-skeleton starts with `skel` (exact matches first in the caller's ranking).
    func soundsLike(_ skel: String, limit: Int = 120) -> [(skel: String, word: String, count: Int)] {
        guard let t = lex, !skel.isEmpty else { return [] }
        return t.prefixed(Array((skel).utf8), limit: limit).compactMap { i in
            let f = t.fields(i); return f.count == 3 ? (f[0], f[1], Int(f[2]) ?? 1) : nil
        }
    }

    /// How common a word is (0 = not in the dictionary).
    func count(_ word: String) -> Int {
        if let c = freqCache[word] { return c }
        guard let t = words else { return 0 }
        let key = Array((word + "\t").utf8)
        let i = t.lowerBound(key)
        var c = 0
        if i < t.count { let f = t.fields(i); if f.count == 2, f[0] == word { c = Int(f[1]) ?? 0 } }
        if freqCache.count > 4000 { freqCache.removeAll(keepingCapacity: true) }
        freqCache[word] = c
        return c
    }

    /// Dictionary words that start with these letters (Wijesekara / typed Sinhala), most common first.
    func completions(_ prefix: String, limit: Int = 60) -> [(word: String, count: Int)] {
        guard let t = words, !prefix.isEmpty else { return [] }
        return t.prefixed(Array(prefix.utf8), limit: 400).compactMap { i -> (String, Int)? in
            let f = t.fields(i); return f.count == 2 ? (f[0], Int(f[1]) ?? 0) : nil
        }.sorted { $0.1 > $1.1 }.prefix(limit).map { $0 }
    }

    /// How often w2 followed w1 in the corpus.
    func pairCount(_ w1: String, _ w2: String) -> Int {
        guard let t = bigrams else { return 0 }
        let key = Array((w1 + "\t" + w2 + "\t").utf8)
        let rows = t.prefixed(key, limit: 1)
        guard let i = rows.first else { return 0 }
        let f = t.fields(i); return f.count == 3 ? Int(f[2]) ?? 0 : 0
    }
}
