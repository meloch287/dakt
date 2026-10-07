import XCTest
@testable import DaktRecorder

final class QuestionGateTests: XCTestCase {
    func testShortAndUnpunctuatedQuestionsTriggerAnswer() {
        for text in ["Почему?", "А как это работает", "можно ли ускорить загрузку", "Расскажите о решении", "What is latency", "Explain the tradeoff"] {
            XCTAssertTrue(QuestionGate.shouldAnswer(text), text)
        }
    }

    func testAcknowledgmentsAndSilenceDoNotTriggerAnswer() {
        for text in ["", "  ", "Да", "ага", "Спасибо большое", "Продолжаем обсуждение проекта"] {
            XCTAssertFalse(QuestionGate.shouldAnswer(text), text)
        }
    }

    func testCumulativeSpeechIsNotAskedTwice() {
        var buffer = UtteranceBuffer()
        XCTAssertEqual(buffer.update("Как это работает"), "Как это работает")
        XCTAssertEqual(buffer.commit("Как это работает?"), "Как это работает?")
        XCTAssertNil(buffer.commit("Как это работает?"))
        XCTAssertEqual(buffer.update("Как это работает? А сколько стоит?"), "А сколько стоит?")
        XCTAssertEqual(buffer.commit("Как это работает? А сколько стоит?"), "А сколько стоит?")
        buffer.reset()
        XCTAssertEqual(buffer.commit("Почему?"), "Почему?")
    }
}
