import XCTest

final class TranslatorTests: XCTestCase {
    func testParsePlainJSON() {
        let r = Translator.parse(#"{"language":"Hebrew","code":"he","translation":"ඔයාට කොහොමද?"}"#, fallbackTranslation: "x")
        XCTAssertEqual(r.translation, "ඔයාට කොහොමද?")
        XCTAssertEqual(r.source?.code, "he")
        XCTAssertNil(r.transcript)
    }
    func testParseFencedJSONWithTranscript() {
        let raw = "```json\n{\"transcript\":\"שלום\",\"language\":\"Hebrew\",\"code\":\"iw\",\"translation\":\"ආයුබෝවන්\"}\n```"
        let r = Translator.parse(raw, fallbackTranslation: "x")
        XCTAssertEqual(r.transcript, "שלום")
        XCTAssertEqual(r.source?.name, "Hebrew")
        XCTAssertEqual(r.translation, "ආයුබෝවන්")
    }
    func testParseFallsBackToRawText() {
        let r = Translator.parse("just text", fallbackTranslation: "just text")
        XCTAssertEqual(r.translation, "just text")
        XCTAssertNil(r.source)
    }
    func testLanguageLookup() {
        XCTAssertEqual(Translator.language("zh-CN")?.code, "zh")
        XCTAssertEqual(Translator.language(named: "sinhala")?.code, "si")
        XCTAssertNil(Translator.language("xx"))
    }
    func testRecentLanguageGoesOnTop() {
        Translator.touch(Translator.language("ko")!)
        Translator.touch(Translator.language("he")!)
        XCTAssertEqual(Translator.ordered.first?.code, "he")
        XCTAssertEqual(Translator.ordered[1].code, "ko")
        XCTAssertEqual(Set(Translator.ordered.map(\.code)).count, Translator.all.count)
    }
    func testMimeForVoiceNotes() {
        XCTAssertEqual(Translator.mime(forExtension: "opus"), "audio/ogg")
        XCTAssertEqual(Translator.mime(forExtension: "M4A"), "audio/mp4")
    }
}

final class LearningTests: XCTestCase {
    func testPickedWordBecomesFirstForThatSpelling() {
        let ws = WordStore.shared
        ws.waitUntilLoaded()
        ws.forgetAll()
        SharedStore.shared[bool: SharedStore.K.learnWords] = true
        let direct = Singlish.convert("kohomada")
        XCTAssertEqual(ws.sinhalaSuggestions(roman: "kohomada").list.first, direct)
        // the user taps a different suggestion for this spelling
        ws.learn("කොහොමද", roman: "kohomada", previous: nil, chosen: true, rejected: direct)
        let r = ws.sinhalaSuggestions(roman: "kohomada")
        XCTAssertEqual(r.list.first, "කොහොමද")
        XCTAssertLessThanOrEqual(r.list.count, 3)
    }
    func testNextWordPrediction() {
        let ws = WordStore.shared
        ws.waitUntilLoaded()
        ws.forgetAll()
        SharedStore.shared[bool: SharedStore.K.learnWords] = true
        ws.learn(fromText: "සුබ උදෑසනක් වේවා\nසුබ උදෑසනක් මචං\nසුබ රාත්‍රියක්")
        XCTAssertEqual(ws.nextWords(context: ["සුබ"]).first, "උදෑසනක්")
        ws.forgetAll()
    }
}

final class PersonalLMTests: XCTestCase {
    func testKneserNeyPrefersSeenContinuation() {
        var lm = PersonalLM()
        for _ in 0..<5 { lm.observe("කොහොමද", context: ["ඔයා"]) }
        lm.observe("කොහෙද", context: ["ඔයා"])
        lm.observe("කොහෙද", context: ["එයා"])
        XCTAssertGreaterThan(lm.p("කොහොමද", ["ඔයා"]), lm.p("කොහෙද", ["ඔයා"]))
        XCTAssertGreaterThan(lm.p("කොහොමද", ["ඔයා"]), 0.4)
        XCTAssertGreaterThan(lm.p("unknown", ["ඔයා"]), 0)        // never zero
        XCTAssertEqual(lm.predict(["ඔයා"], k: 1).first?.0, "කොහොමද")
    }
    func testProbabilitiesRoughlySumToOne() {
        var lm = PersonalLM()
        let text = "a b c a b d a b c b c a".split(separator: " ").map(String.init)
        var ctx: [String] = []
        for w in text { lm.observe(w, context: ctx); ctx.append(w) }
        let sum = ["a", "b", "c", "d"].map { lm.p($0, ["a", "b"]) }.reduce(0, +)
        XCTAssertGreaterThan(sum, 0.3); XCTAssertLessThanOrEqual(sum, 1.0001)
    }
    func testNextLetterPrediction() {
        var lm = PersonalLM()
        for _ in 0..<4 { lm.observeChars("kohomada") }
        lm.observeChars("koheda")
        XCTAssertGreaterThan(lm.pChar("o", after: "^koh"), lm.pChar("e", after: "^koh"))
        XCTAssertGreaterThan(lm.pChar("m", after: "^koho"), lm.pChar("n", after: "^koho"))
    }
}
