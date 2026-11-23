import UIKit

enum KeyKind: Equatable {
    case char(String)
    case shift, backspace, space, ret, globe, emoji, lang
    case page(KeyPage)
    case spacer
}

enum KeyPage: Equatable { case letters, numbers, symbols, sinhala1, sinhala2 }

/// One alternate shown on long-press: what is displayed and what is typed.
/// In Singlish mode `value` is roman appended to the word being composed; `direct` = insert as-is.
struct KeyAlt { let display: String; let value: String; var direct: Bool = false }

struct KeySpec {
    let kind: KeyKind
    var label: String
    var hint: String? = nil
    var width: CGFloat = 1
    var alts: [KeyAlt] = []
    var isSpecial: Bool {
        switch kind {
        case .char, .space, .spacer: return false
        default: return true
        }
    }
}

enum KeyLayout {
    static let topRow = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    static let midRow = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    static let lowRow = ["z", "x", "c", "v", "b", "n", "m"]
    static let numbers = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// Sinhala shown on each Singlish key (lower, upper)
    static func singlishHint(_ letter: String, upper: Bool) -> String? {
        let k = upper ? letter.uppercased() : letter
        if let c = Singlish.consonants[k] { return c }
        if let v = Singlish.vowels[k] { return v.0 }
        if let s = Singlish.specials[k] { return s }
        return nil
    }

    static let singlishAlts: [String: [(String, String)]] = [
        "a": [("ආ", "aa"), ("ඇ", "ae"), ("ඈ", "aee"), ("ඓ", "ai"), ("ඖ", "au")],
        "e": [("ඒ", "E"), ("ඊ", "ee"), ("ඓ", "ai")],
        "i": [("ඊ", "ii")],
        "o": [("ඕ", "O"), ("ඖ", "au")],
        "u": [("ඌ", "uu"), ("ඍ", "Ru")],
        "k": [("ඛ", "K")],
        "g": [("ඝ", "G"), ("ඟ", "zg"), ("ඥ", "gn")],
        "c": [("ඡ", "C")],
        "j": [("ඣ", "J"), ("ඦ", "zj")],
        "t": [("ත", "th"), ("ඨ", "T"), ("ථ", "Th")],
        "d": [("ද", "dh"), ("ඪ", "D"), ("ධ", "Dh"), ("ඬ", "zd"), ("ඳ", "zdh")],
        "n": [("ණ", "N"), ("ං", "x"), ("ඤ", "kn"), ("ඞ", "X"), ("ඳ", "zdh")],
        "p": [("ඵ", "P")],
        "b": [("භ", "B"), ("ඹ", "zb")],
        "s": [("ශ", "sh"), ("ෂ", "S")],
        "l": [("ළ", "L")],
        "h": [("ඃ", "H")],
        "r": [("ඍ", "Ru")],
        "x": [("ඞ", "X")],
    ]

    static let englishAlts: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "ã", "å", "æ"], "e": ["è", "é", "ê", "ë", "ē"], "i": ["ì", "í", "î", "ï"], "o": ["ò", "ó", "ô", "ö", "õ", "ø", "œ"],
        "u": ["ù", "ú", "û", "ü"], "n": ["ñ"], "c": ["ç"], "s": ["ß", "$"], "y": ["ÿ"],
    ]

    static func letters(singlish: Bool, upper: Bool, numberRow: Bool, hints: Bool, showGlobe: Bool) -> [[KeySpec]] {
        func key(_ l: String, num: String? = nil) -> KeySpec {
            let label = upper ? l.uppercased() : l
            var alts: [KeyAlt] = []
            if let n = num { alts.append(KeyAlt(display: n, value: n, direct: true)) }
            if singlish {
                for (d, v) in singlishAlts[l] ?? [] { alts.append(KeyAlt(display: d, value: v)) }
            } else {
                for a in englishAlts[l] ?? [] { alts.append(KeyAlt(display: upper ? a.uppercased() : a, value: upper ? a.uppercased() : a, direct: true)) }
            }
            return KeySpec(kind: .char(label), label: label, hint: singlish && hints ? singlishHint(l, upper: upper) : nil, alts: alts)
        }
        var rows: [[KeySpec]] = []
        if numberRow { rows.append(numbers.map { KeySpec(kind: .char($0), label: $0) }) }
        rows.append(topRow.enumerated().map { key($0.element, num: numberRow ? nil : numbers[$0.offset]) })
        rows.append([KeySpec(kind: .spacer, label: "", width: 0.5)] + midRow.map { key($0) } + [KeySpec(kind: .spacer, label: "", width: 0.5)])
        rows.append([KeySpec(kind: .shift, label: "shift", width: 1.35), KeySpec(kind: .spacer, label: "", width: 0.15)] + lowRow.map { key($0) } + [KeySpec(kind: .spacer, label: "", width: 0.15), KeySpec(kind: .backspace, label: "delete", width: 1.35)])
        rows.append(bottomRow(singlish: singlish, page: .letters, showGlobe: showGlobe))
        return rows
    }

    static func bottomRow(singlish: Bool, page: KeyPage, showGlobe: Bool) -> [KeySpec] {
        var r: [KeySpec] = [KeySpec(kind: .page(page == .letters ? .numbers : .letters), label: page == .letters ? "123" : "ABC", width: 1.3)]
        if showGlobe { r.append(KeySpec(kind: .globe, label: "globe", width: 1.1)) }
        r.append(KeySpec(kind: .emoji, label: "emoji", width: 1.1))
        if singlish { r.append(KeySpec(kind: .page(page == .sinhala1 || page == .sinhala2 ? .letters : .sinhala1), label: page == .sinhala1 || page == .sinhala2 ? "abc" : "අ", width: 1.1)) }
        r.append(KeySpec(kind: .space, label: singlish ? "සිංහල" : "English", width: showGlobe ? 3.6 : 4.4))
        r.append(KeySpec(kind: .lang, label: singlish ? "EN" : "සිං", width: 1.1))
        r.append(KeySpec(kind: .ret, label: "return", width: 1.9))
        return r
    }

    static func numbersPage(symbols: Bool, singlish: Bool, showGlobe: Bool) -> [[KeySpec]] {
        let r1 = symbols ? ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="] : numbers
        let r2 = symbols ? ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"] : ["-", "/", ":", ";", "(", ")", "රු", "&", "@", "\""]
        let r3 = symbols ? [".", ",", "?", "!", "'"] : [".", ",", "?", "!", "'"]
        return [
            r1.map { KeySpec(kind: .char($0), label: $0) },
            r2.map { KeySpec(kind: .char($0), label: $0) },
            [KeySpec(kind: .page(symbols ? .numbers : .symbols), label: symbols ? "123" : "#+=", width: 1.35), KeySpec(kind: .spacer, label: "", width: 0.5)]
                + r3.map { KeySpec(kind: .char($0), label: $0, width: 1.4) }
                + [KeySpec(kind: .spacer, label: "", width: 0.5), KeySpec(kind: .backspace, label: "delete", width: 1.35)],
            bottomRow(singlish: singlish, page: .numbers, showGlobe: showGlobe),
        ]
    }

    // Sinhala letters, typed directly (for rare letters & signs)
    static let sinhala1: [[String]] = [
        ["අ", "ආ", "ඇ", "ඈ", "ඉ", "ඊ", "උ", "ඌ", "එ", "ඒ"],
        ["ඔ", "ඕ", "ඓ", "ඖ", "ඍ", "ඎ", "ං", "ඃ", "ඞ", "ඥ"],
        ["ක", "ඛ", "ග", "ඝ", "ඟ", "ච", "ඡ", "ජ", "ඣ", "ඤ"],
    ]
    static let sinhala2: [[String]] = [
        ["ට", "ඨ", "ඩ", "ඪ", "ණ", "ඬ", "ත", "ථ", "ද", "ධ"],
        ["න", "ඳ", "ප", "ඵ", "බ", "භ", "ම", "ඹ", "ය", "ර"],
        ["ල", "ව", "ශ", "ෂ", "ස", "හ", "ළ", "ෆ", "ඦ", "ඏ"],
        ["්", "ා", "ැ", "ෑ", "ි", "ී", "ු", "ූ", "ෘ", "ෙ"],
        ["ේ", "ෛ", "ො", "ෝ", "ෞ", "ෟ", "ෲ", "\u{200D}", "෴", "ඐ"],
    ]

    static func sinhalaPage(_ page: KeyPage, showGlobe: Bool) -> [[KeySpec]] {
        let grid = page == .sinhala1 ? sinhala1 : Array(sinhala2.prefix(3))
        var rows: [[KeySpec]] = grid.map { row in row.map { KeySpec(kind: .char($0), label: $0) } }
        let signs = page == .sinhala1 ? ["ා", "ැ", "ෑ", "ි", "ී", "ු", "ූ", "ෙ"] : ["්", "ෘ", "ේ", "ෛ", "ො", "ෝ", "ෞ", "\u{200D}"]
        let toggle = KeySpec(kind: .page(page == .sinhala1 ? .sinhala2 : .sinhala1), label: page == .sinhala1 ? "1/2" : "2/2", width: 1.3)
        rows.append([toggle] + signs.map { KeySpec(kind: .char($0), label: $0 == "\u{200D}" ? "ZWJ" : "◌" + $0) } + [KeySpec(kind: .backspace, label: "delete", width: 1.3)])
        rows.append(bottomRow(singlish: true, page: page, showGlobe: showGlobe))
        return rows
    }
}
