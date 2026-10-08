import XCTest
@testable import DaktRecorder

final class AnswerEngineTests: XCTestCase {
    @MainActor
    func testStopClearsQueuedQuestionsAndIgnoresLateCompletion() async {
        let first = expectation(description: "first")
        var started: [String] = []
        var release: CheckedContinuation<String, Never>?
        let engine = AnswerEngine { question, _, _, _ in
            started.append(question)
            return await withCheckedContinuation { release = $0; first.fulfill() }
        }
        engine.ask("первый", recent: [], config: LunaConfiguration())
        await fulfillment(of: [first], timeout: 2)
        engine.ask("второй", recent: [], config: LunaConfiguration())
        engine.ask("третий", recent: [], config: LunaConfiguration())
        XCTAssertEqual(engine.pendingCount, 2)
        engine.clear()
        release?.resume(returning: "Поздний ответ")
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(started, ["первый"])
        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertNil(engine.reply)
    }

    @MainActor
    func testFailureWaitsForRetryWithoutLosingTheNextQuestion() async {
        let failed = expectation(description: "initial failure")
        let completed = expectation(description: "next question completed")
        var calls: [String] = []
        var attempts = 0
        let engine = AnswerEngine { question, _, config, _ in
            calls.append(question)
            attempts += 1
            if attempts == 1 {
                failed.fulfill()
                throw RecorderError.message("Временная ошибка")
            }
            XCTAssertEqual(config.apiKey, "fresh-test-key")
            if question == "второй" { completed.fulfill() }
            return "Ответ на \(question)"
        }
        engine.ask("первый", recent: [], config: LunaConfiguration(apiKey: "old-test-key"))
        engine.ask("второй", recent: [], config: LunaConfiguration(apiKey: "old-test-key"))
        await fulfillment(of: [failed], timeout: 2)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(calls, ["первый"])
        XCTAssertEqual(engine.pendingCount, 1)
        XCTAssertNotNil(engine.error)
        engine.retry(config: LunaConfiguration(apiKey: "fresh-test-key"))
        await fulfillment(of: [completed], timeout: 2)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(calls, ["первый", "первый", "второй"])
        XCTAssertEqual(engine.history.first?.text, "Ответ на первый")
        XCTAssertEqual(engine.reply?.text, "Ответ на второй")
        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertNil(engine.error)
    }

    @MainActor
    func testCancelAfterFailureAllowsAFreshSession() async {
        let failed = expectation(description: "failed request")
        let next = expectation(description: "new session request")
        let engine = AnswerEngine { question, _, _, _ in
            if question == "ошибка" {
                failed.fulfill()
                throw RecorderError.message("Временная ошибка")
            }
            next.fulfill()
            return "Новый ответ"
        }
        engine.ask("ошибка", recent: [], config: LunaConfiguration())
        await fulfillment(of: [failed], timeout: 2)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertNotNil(engine.error)
        engine.cancel()
        engine.ask("новая сессия", recent: [], config: LunaConfiguration())
        await fulfillment(of: [next], timeout: 2)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(engine.reply?.text, "Новый ответ")
    }

    @MainActor
    func testAutomaticQuestionWaitsForTheWholePreviousAnswer() async {
        let first = expectation(description: "first started")
        let second = expectation(description: "second started")
        var started: [String] = []
        var pending: [String: CheckedContinuation<String, Never>] = [:]
        let engine = AnswerEngine { question, _, _, partial in
            started.append(question)
            partial("Начало")
            return await withCheckedContinuation { continuation in
                pending[question] = continuation
                (question == "первый" ? first : second).fulfill()
            }
        }
        engine.ask("первый", recent: [], config: LunaConfiguration())
        await fulfillment(of: [first], timeout: 2)
        engine.ask("второй", recent: [], config: LunaConfiguration())
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(started, ["первый"], "New automatic speech must not cancel the active request")
        pending["первый"]?.resume(returning: "Первый ответ целиком, включая окончание.")
        await fulfillment(of: [second], timeout: 2)
        pending["второй"]?.resume(returning: "Второй ответ целиком.")
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(engine.history.first?.text, "Первый ответ целиком, включая окончание.")
        XCTAssertEqual(engine.reply?.text, "Второй ответ целиком.")
    }

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
        engine.ask("новый", recent: [], config: LunaConfiguration(), interrupt: true)
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
