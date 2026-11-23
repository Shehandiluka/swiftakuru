import Foundation

/// Helakuru-style Singlish → Sinhala Unicode transliteration.
///  t=ට th=ත d=ඩ dh=ද  T=ඨ Th=ථ D=ඪ Dh=ධ  N=ණ L=ළ  x=ං  zg=ඟ zd=ඬ zdh=ඳ zb=ඹ
///  a=අ aa=ආ ae/A=ඇ aae/AA=ඈ i=ඉ ii/ee=ඊ u=උ uu=ඌ e=එ E/ea=ඒ o=ඔ O/oo=ඕ ai=ඓ au=ඖ Ru=ඍ
///  consonant + r/y + vowel → rakaransaya / yansaya (ක්‍ර, ක්‍ය)
enum Singlish {
    // MARK: tables (BEGIN-TABLES — parsed by tests/singlish.test.js, keep one entry per line)
    static let vowels: [String: (String, String)] = [
        "a": ("අ", ""),
        "aa": ("ආ", "ා"),
        "A": ("ඇ", "ැ"),
        "ae": ("ඇ", "ැ"),
        "AA": ("ඈ", "ෑ"),
        "Aa": ("ඈ", "ෑ"),
        "aae": ("ඈ", "ෑ"),
        "aee": ("ඈ", "ෑ"),
        "i": ("ඉ", "ි"),
        "ii": ("ඊ", "ී"),
        "ee": ("ඊ", "ී"),
        "I": ("ඊ", "ී"),
        "u": ("උ", "ු"),
        "uu": ("ඌ", "ූ"),
        "U": ("ඌ", "ූ"),
        "e": ("එ", "ෙ"),
        "E": ("ඒ", "ේ"),
        "ea": ("ඒ", "ේ"),
        "o": ("ඔ", "ො"),
        "O": ("ඕ", "ෝ"),
        "oo": ("ඕ", "ෝ"),
        "ai": ("ඓ", "ෛ"),
        "au": ("ඖ", "ෞ"),
        "ou": ("ඖ", "ෞ"),
        "Ru": ("ඍ", "ෘ"),
        "RU": ("ඎ", "ෲ"),
    ]
    static let consonants: [String: String] = [
        "k": "ක",
        "kh": "ඛ",
        "K": "ඛ",
        "g": "ග",
        "gh": "ඝ",
        "G": "ඝ",
        "X": "ඞ",
        "zg": "ඟ",
        "c": "ච",
        "ch": "ච",
        "C": "ඡ",
        "Ch": "ඡ",
        "j": "ජ",
        "jh": "ඣ",
        "J": "ඣ",
        "kn": "ඤ",
        "gn": "ඥ",
        "GN": "ඥ",
        "zj": "ඦ",
        "t": "ට",
        "T": "ඨ",
        "d": "ඩ",
        "D": "ඪ",
        "N": "ණ",
        "zd": "ඬ",
        "th": "ත",
        "Th": "ථ",
        "dh": "ද",
        "Dh": "ධ",
        "n": "න",
        "zdh": "ඳ",
        "p": "ප",
        "ph": "ඵ",
        "P": "ඵ",
        "b": "බ",
        "bh": "භ",
        "B": "භ",
        "m": "ම",
        "zb": "ඹ",
        "y": "ය",
        "r": "ර",
        "l": "ල",
        "v": "ව",
        "w": "ව",
        "sh": "ශ",
        "Sh": "ෂ",
        "S": "ෂ",
        "s": "ස",
        "h": "හ",
        "L": "ළ",
        "f": "ෆ",
        "F": "ෆ",
        "q": "ක",
    ]
    static let specials: [String: String] = [
        "x": "ං",
        "H": "ඃ",
    ]
    // END-TABLES

    static let hal = "\u{0DCA}"
    static let zwj = "\u{200D}"

    private enum Tok { case cons(String), vowel(String, String), special(String), other(String) }

    private static func match(_ s: [Character], _ i: Int) -> (Tok, Int) {
        let maxLen = min(3, s.count - i)
        if maxLen >= 1 {
            // longest match; at each length an exact (case-sensitive) match wins over a case-insensitive one
            for len in stride(from: maxLen, through: 1, by: -1) {
                let exact = String(s[i..<(i + len)])
                for sub in [exact, exact.lowercased()] {
                    if let c = consonants[sub] { return (.cons(c), len) }
                    if let v = vowels[sub] { return (.vowel(v.0, v.1), len) }
                    if let sp = specials[sub] { return (.special(sp), len) }
                }
            }
        }
        return (.other(String(s[i])), 1)
    }

    /// Converts a Singlish string (one word or more) to Sinhala.
    static func convert(_ roman: String) -> String {
        let s = Array(roman)
        var out = ""
        var i = 0
        while i < s.count {
            let (tok, len) = match(s, i)
            switch tok {
            case .cons(let c):
                let j = i + len
                if j < s.count, case .vowel(_, let sign) = match(s, j).0 {
                    let vlen = match(s, j).1
                    out += c + sign
                    i = j + vlen
                    continue
                }
                // rakaransaya / yansaya: C + r|y + vowel
                if j < s.count, c != "ර", c != "ය" {
                    let (next, nlen) = match(s, j)
                    if case .cons(let n) = next, n == "ර" || n == "ය", j + nlen < s.count, case .vowel = match(s, j + nlen).0 {
                        out += c + hal + zwj
                        i = j
                        continue
                    }
                }
                out += c + hal
                i = j
            case .vowel(let ind, _):
                out += ind
                i += len
            case .special(let sp):
                out += sp
                i += len
            case .other(let o):
                out += o
                i += len
            }
        }
        return out
    }

    /// Spelling variants people commonly mean (t/th, d/dh, n/N, l/L, s/sh, ee/E, oo/uu, nd/ඳ, ng/ඟ, mb/ඹ)
    static let variantRules: [(String, String)] = [
        ("th", "t"), ("t", "th"), ("dh", "d"), ("d", "dh"), ("n", "N"), ("l", "L"), ("s", "sh"), ("sh", "s"),
        ("ee", "E"), ("oo", "uu"), ("uu", "oo"), ("nd", "zdh"), ("ng", "zg"), ("mb", "zb"), ("ndh", "zdh"), ("e", "E"), ("a", "aa"), ("i", "ii"), ("u", "uu"),
    ]

    /// Returns alternative Sinhala spellings for a roman word (each rule applied once at each position).
    static func variants(_ roman: String, limit: Int = 24) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let base = convert(roman)
        seen.insert(base)
        for (from, to) in variantRules {
            var searchStart = roman.startIndex
            while let r = roman.range(of: from, range: searchStart..<roman.endIndex) {
                // avoid t→th when already "th", etc.
                let after = roman[r.upperBound...]
                let skip = (from == "t" && after.hasPrefix("h")) || (from == "d" && after.hasPrefix("h")) || (from == "s" && after.hasPrefix("h"))
                    || (from == "a" && after.hasPrefix("a")) || (from == "i" && after.hasPrefix("i")) || (from == "u" && after.hasPrefix("u"))
                if !skip {
                    let alt = roman.replacingCharacters(in: r, with: to)
                    let si = convert(alt)
                    if !seen.contains(si) { seen.insert(si); out.append(si); if out.count >= limit { return out } }
                }
                searchStart = r.upperBound
            }
        }
        return out
    }

    // MARK: skeletons (fuzzy keys used to match dictionary words)
    static func romanSkeleton(_ roman: String) -> String {
        var r = roman.lowercased()
        for (a, b) in [("zdh", "nd"), ("zd", "nd"), ("zg", "ng"), ("zb", "mb"), ("zj", "nj"), ("x", "n"), ("w", "v"), ("aee", "a"), ("aae", "a"), ("ae", "a"), ("ee", "i"), ("oo", "u"), ("ea", "e"), ("ou", "au"), ("nd", "d"), ("ng", "g"), ("mb", "b")] {
            r = r.replacingOccurrences(of: a, with: b)
        }
        // aspiration markers: kh→k, th→t ...
        var out = ""
        var prev: Character = " "
        let chars = Array(r)
        for (i, ch) in chars.enumerated() {
            // "hodayi" ≈ "hodai": drop y between vowels
            if ch == "y", "aeiou".contains(prev), i + 1 < chars.count, "aeiou".contains(chars[i + 1]) { continue }
            if ch == "h", "kgcjtdpbs".contains(prev) { continue }
            if ch == prev, "aeiou".contains(ch) { continue }
            if ch == prev, !"aeiou".contains(ch) { continue } // double consonants (thaththa → tata)
            out.append(ch)
            prev = ch
        }
        return out
    }

    static let sinhalaRoman: [Character: String] = [
        "අ": "a", "ආ": "a", "ඇ": "a", "ඈ": "a", "ඉ": "i", "ඊ": "i", "උ": "u", "ඌ": "u", "ඍ": "ru", "ඎ": "ru", "එ": "e", "ඒ": "e", "ඓ": "ai", "ඔ": "o", "ඕ": "o", "ඖ": "au",
        "ක": "k", "ඛ": "k", "ග": "g", "ඝ": "g", "ඞ": "n", "ඟ": "ng", "ච": "c", "ඡ": "c", "ජ": "j", "ඣ": "j", "ඤ": "kn", "ඥ": "gn", "ඦ": "nj",
        "ට": "t", "ඨ": "t", "ඩ": "d", "ඪ": "d", "ණ": "n", "ඬ": "nd", "ත": "t", "ථ": "t", "ද": "d", "ධ": "d", "න": "n", "ඳ": "nd",
        "ප": "p", "ඵ": "p", "බ": "b", "භ": "b", "ම": "m", "ඹ": "mb", "ය": "y", "ර": "r", "ල": "l", "ව": "v", "ශ": "s", "ෂ": "s", "ස": "s", "හ": "h", "ළ": "l", "ෆ": "f",
    ]
    static let signRoman: [Character: String] = [
        "ා": "a", "ැ": "a", "ෑ": "a", "ි": "i", "ී": "i", "ු": "u", "ූ": "u", "ෘ": "ru", "ෲ": "ru", "ෙ": "e", "ේ": "e", "ෛ": "ai", "ො": "o", "ෝ": "o", "ෞ": "au", "ෟ": "lu",
    ]

    /// Sinhala word → fuzzy roman skeleton (same space as romanSkeleton)
    static func sinhalaSkeleton(_ si: String) -> String {
        var roman = ""
        let scalars = Array(si.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let ch = Character(scalars[i])
            if let c = sinhalaRoman[ch], scalars[i].value >= 0x0D9A {
                roman += c
                // inherent 'a' unless followed by a sign / hal
                let next: Character? = i + 1 < scalars.count ? Character(scalars[i + 1]) : nil
                if let n = next, signRoman[n] != nil || n == "්" {
                    // handled by next iteration
                } else {
                    roman += "a"
                }
            } else if let v = sinhalaRoman[ch] {
                roman += v
            } else if let s = signRoman[ch] {
                roman += s
            } else if ch == "ං" {
                roman += "n"
            } else if ch == "්" || ch == "\u{200D}" || ch == "ඃ" {
                // nothing
            } else {
                roman.append(ch)
            }
            i += 1
        }
        return romanSkeleton(roman)
    }

    static func isSinhala(_ s: String) -> Bool { s.unicodeScalars.contains { $0.value >= 0x0D80 && $0.value <= 0x0DFF } }
}
