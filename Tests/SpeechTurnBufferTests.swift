import XCTest
@testable import DaktRecorder

final class SpeechTurnBufferTests: XCTestCase {
    func testTechnicalSegmentsBecomeOneCompleteQuestion() {
        var buffer = SpeechTurnBuffer()
        XCTAssertNil(buffer.append("Расскажите про ваш проект", endsTurn: false))
        XCTAssertNil(buffer.append("и работу с очередями.", endsTurn: false))
        XCTAssertEqual(buffer.append("Как вы находили узкие места?", endsTurn: true),
                       "Расскажите про ваш проект и работу с очередями. Как вы находили узкие места?")
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.append("Новый вопрос?", endsTurn: true), "Новый вопрос?")
    }

    func testEmptyFinalMarkerFinishesTheLastFullAudioSegment() {
        var buffer = SpeechTurnBuffer()
        _ = buffer.append("Вопрос ровно на границе файла?", endsTurn: false)
        XCTAssertEqual(buffer.append("", endsTurn: true), "Вопрос ровно на границе файла?")
        XCTAssertNil(buffer.append("", endsTurn: true))
    }

    func testResetDoesNotLeakSpeechAcrossSessions() {
        var buffer = SpeechTurnBuffer()
        _ = buffer.append("Старый вопрос", endsTurn: false)
        buffer.reset()
        XCTAssertEqual(buffer.append("Новый вопрос?", endsTurn: true), "Новый вопрос?")
    }

    func testTimingPreferenceIsBoundedAndFinite() {
        XCTAssertEqual(SpeechTiming.normalized(.nan), 1.2)
        XCTAssertEqual(SpeechTiming.normalized(0.1), 0.4)
        XCTAssertEqual(SpeechTiming.normalized(10), 2.5)
        XCTAssertEqual(SpeechTiming.normalized(1.6), 1.6)
    }
}
