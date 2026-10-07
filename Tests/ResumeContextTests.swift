import XCTest
@testable import DaktRecorder

final class ResumeContextTests: XCTestCase {
    private func inputText(_ body: [String: Any]) -> String {
        let messages = body["input"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    func testResumeIsAvailableToAnswersAsData() {
        var config = LunaConfiguration(apiKey: "test")
        config.resume = "Кандидат: Python, FastAPI. Снизил ожидание со 120 до 80 секунд."
        let body = LunaService.body(question: "Расскажи о своём опыте", recent: [], config: config)
        XCTAssertTrue(inputText(body).contains("Снизил ожидание со 120 до 80 секунд"))
        XCTAssertFalse((body["instructions"] as? String ?? "").contains("Снизил ожидание со 120 до 80 секунд"))
    }

    func testTemplateHasSeparateInstructionsAndEnoughOutputBudget() {
        var config = LunaConfiguration(endpoint: "https://proxy.example/v1/responses", apiKey: "test")
        config.resume = "Python-разработчик, FastAPI, PostgreSQL."
        let body = LunaService.body(question: "Техническая встреча", recent: [], config: config, purpose: .meetingTemplate)
        XCTAssertTrue((body["instructions"] as? String ?? "").contains("Самопрезентация"))
        XCTAssertEqual(body["max_output_tokens"] as? Int, 2_000)
        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "none")
    }

    func testTemplateDoesNotReuseOldMeetingOrConversationAsResumeFacts() {
        var config = LunaConfiguration(apiKey: "test")
        config.resume = "Новый кандидат: Python."
        config.context = "OLD_MEETING_CONTENT"
        let body = LunaService.body(question: "Новая компания", recent: ["OLD_SPOKEN_LINE"], config: config, purpose: .meetingTemplate)
        let input = inputText(body)
        XCTAssertTrue(input.contains("Новый кандидат"))
        XCTAssertTrue(input.contains("Новая компания"))
        XCTAssertFalse(input.contains("OLD_SPOKEN_LINE"))
        XCTAssertFalse((body["instructions"] as? String ?? "").contains("OLD_MEETING_CONTENT"))
    }
}
