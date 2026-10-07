import XCTest
@testable import DaktRecorder

final class AnswerEngineTests: XCTestCase {
    @MainActor
    func testLateOldAnswerCannotOverwriteNewQuestion() async {
        let first = expectation(description: "first request")
        let second = expectation(description: "second request")
        var pending: [String: CheckedContinuation<String, Never>] = [:]
        let engine = AnswerEngine { question, _, _, _ in
            await withCheckedContinuation { continuation in
                pending[question] = continuation
                (question == "старый" ? first : second).fulfill()
            }
        }
        engine.ask("старый", recent: [], config: LunaConfiguration())
        await fulfillment(of: [first], timeout: 2)
        engine.ask("новый", recent: [], config: LunaConfiguration())
        await fulfillment(of: [second], timeout: 2)
        pending["новый"]?.resume(returning: "актуальный ответ")
        for _ in 0..<10 { await Task.yield() }
        pending["старый"]?.resume(returning: "устаревший ответ")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(engine.reply?.question, "новый")
        XCTAssertEqual(engine.reply?.text, "актуальный ответ")
        XCTAssertEqual(engine.reply?.isStreaming, false)
        XCTAssertNil(engine.error)
    }

    @MainActor
    func testStopIgnoresEvenUncooperativeTransport() async {
        let started = expectation(description: "started")
        var pending: CheckedContinuation<String, Never>?
        let engine = AnswerEngine { _, _, _, _ in
            await withCheckedContinuation { continuation in
                pending = continuation
                started.fulfill()
            }
        }
        engine.ask("вопрос", recent: [], config: LunaConfiguration())
        await fulfillment(of: [started], timeout: 2)
        engine.clear()
        pending?.resume(returning: "поздний ответ")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(engine.reply)
        XCTAssertNil(engine.error)
    }
}
