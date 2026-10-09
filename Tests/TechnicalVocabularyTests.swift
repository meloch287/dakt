import XCTest
@testable import DaktRecorder

final class TechnicalVocabularyTests: XCTestCase {
    @MainActor
    func testRecognizedQuestionUsesTechnicalSpelling() {
        let preferences = AssistantPreferences(preview: true)
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.receive("Что такое апи в питоне?")
        XCTAssertEqual(assistant.transcript.last?.text, "Что такое API в Python?")
    }

    @MainActor
    func testSelectingAPIResolvesTheLatestQuestionAndHidesAlternatives() throws {
        let preferences = AssistantPreferences(preview: true)
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.receive("Что такое IP?")
        let api = try XCTUnwrap(assistant.recognitionAlternatives.first { $0.term == "API" })
        assistant.answerAlternative(api)
        XCTAssertEqual(assistant.transcript.last?.text, "Что такое API?")
        XCTAssertTrue(assistant.recognitionAlternatives.isEmpty)
        assistant.receive("Что такое IP?")
        let ip = try XCTUnwrap(assistant.recognitionAlternatives.first { $0.term == "IP" })
        assistant.answerAlternative(ip)
        XCTAssertEqual(assistant.transcript.last?.text, "Что такое IP-адрес?")
        XCTAssertTrue(assistant.recognitionAlternatives.isEmpty)
    }

    @MainActor
    func testOldAlternativeCannotChangeANewerQuestion() throws {
        let assistant = AssistantController(preferences: AssistantPreferences(preview: true), preview: true)
        assistant.receive("Что такое IP?")
        let old = try XCTUnwrap(assistant.recognitionAlternatives.first)
        assistant.receive("Зачем нужен индекс в PostgreSQL?")
        assistant.answerAlternative(old)
        XCTAssertEqual(assistant.transcript.last?.text, "Зачем нужен индекс в PostgreSQL?")
    }

    @MainActor
    func testTurningOffITModePreservesTheOriginalTranscript() {
        let preferences = AssistantPreferences(preview: true)
        preferences.itVocabulary = false
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.receive("Что такое апи в питоне?")
        XCTAssertEqual(assistant.transcript.last?.text, "Что такое апи в питоне?")
        assistant.receive("Что такое IP?")
        XCTAssertTrue(assistant.recognitionAlternatives.isEmpty)
        XCTAssertTrue(preferences.recognitionVocabulary.isEmpty)
    }

    func testAmbiguousPromptIncludesBothQuestionsWithoutAnExtraRequest() {
        let config = LunaConfiguration(apiKey: "test", technicalVocabulary: ["API", "IP", "Python"])
        let body = LunaService.body(question: "Что такое IP?", recent: [], config: config)
        let instructions = body["instructions"] as? String ?? ""
        let messages = body["input"] as? [[String: Any]]
        let content = messages?.first?["content"] as? [[String: Any]]
        let input = content?.first?["text"] as? String ?? ""
        XCTAssertTrue(input.contains("Что такое API?"))
        XCTAssertTrue(input.contains("Что такое IP-адрес?"))
        XCTAssertTrue(instructions.contains("Не выбирай один вариант наугад"))
        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "none")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let network = LunaService.body(question: "Что такое IP-адрес?", recent: [], config: config)
        XCTAssertFalse((network["instructions"] as? String ?? "").contains("Возможна путаница API и IP"))
    }

    func testUnambiguousSpokenTechnologyNamesBecomeCanonicalTerms() {
        XCTAssertEqual(TechnicalVocabulary.normalize("Расскажи про эй пи ай, фаст апи и постгрес."),
                       "Расскажи про API, FastAPI и PostgreSQL.")
        XCTAssertEqual(TechnicalVocabulary.normalize("Что такое апи в питоне?"), "Что такое API в Python?")
    }

    func testIPAndWordsContainingSimilarLettersAreNotChangedToAPI() {
        let text = "IP-адрес 192.168.1.2, IPv6, капитализация и копирование"
        XCTAssertEqual(TechnicalVocabulary.normalize(text), text)
    }

    func testBareIPOffersBothMeaningsWithoutClaimingOneWasSpoken() {
        let choices = TechnicalVocabulary.alternatives(for: "Расскажи что такое IP")
        XCTAssertEqual(choices.map(\.term), ["API", "IP"])
        XCTAssertEqual(choices.map(\.question), ["Расскажи что такое API", "Расскажи что такое IP-адрес"])
    }

    func testExplicitNetworkQuestionsAndComparisonsAreNotAmbiguous() {
        for text in ["Что такое IP-адрес?", "Чем API отличается от IP?", "Как IP связан с TCP?",
                     "Как узнать IP в локальной сети?", "Что такое IPv6?", "Как написать REST API?",
                     "Как NAT меняет IP?", "What is an IP address?",
                     "Что значит IP в интеллектуальной собственности?"] {
            XCTAssertTrue(TechnicalVocabulary.alternatives(for: text).isEmpty, text)
        }
    }

    func testHintsAreBoundedDeduplicatedAndDoNotCopyResumePersonalData() {
        let custom = "gRPC, grpc; Kafka\n" + (0..<250).map { "Service\($0)" }.joined(separator: ",")
        let hints = TechnicalVocabulary.hints(custom: custom,
            context: ["Кандидат: Python и PostgreSQL; person@example.org; +7 999 123 45 67"])
        XCTAssertTrue(hints.contains("API"))
        XCTAssertTrue(hints.contains("IP"))
        XCTAssertTrue(hints.contains("Python"))
        XCTAssertTrue(hints.contains("PostgreSQL"))
        XCTAssertTrue(hints.contains("gRPC"))
        XCTAssertEqual(hints.filter { $0.lowercased() == "grpc" }.count, 1)
        XCTAssertLessThanOrEqual(hints.count, 100)
        XCTAssertFalse(hints.contains { $0.contains("@") || $0.contains("999") || $0.contains("Кандидат") })
    }
}
