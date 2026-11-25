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
        XCTAssertEqual(ws.nextWords(after: "සුබ").first, "උදෑසනක්")
        ws.forgetAll()
    }
}
