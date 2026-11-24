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
