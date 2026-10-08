import XCTest
@testable import DaktRecorder

final class LunaServiceTests: XCTestCase {
    func testLunaUsesNoReasoningAndStreamsThroughResponses() throws {
        let config = LunaConfiguration(endpoint: "https://proxy.example/codex/v1/responses", apiKey: "test", proxyToken: "proxy")
        let request = try LunaService.request(question: "Почему?", recent: [], config: config)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "none")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["max_output_tokens"], "Шлюз Codex не принимает этот параметр")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Proxy-Token"), "proxy")
    }

    func testProxyTokenDoesNotDependOnAPIKey() throws {
        let request = try LunaService.request(question: "Как?", recent: [], config: LunaConfiguration(proxyToken: "proxy"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Proxy-Token"), "proxy")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testRegularResponsesAPIHasBoundedOutput() {
        let config = LunaConfiguration(endpoint: "https://proxy.example/v1/responses", apiKey: "test")
        let body = LunaService.body(question: "q", recent: [], config: config)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 600)
    }

    func testInvalidEndpointAndMissingCredentialsAreRejected() {
        for url in ["http://host/responses", "https://host/chat/completions", "https://user:secret@host/responses", "https://host/responses?key=abc"] {
            XCTAssertThrowsError(try LunaService.request(question: "q", recent: [], config: LunaConfiguration(endpoint: url, apiKey: "k")))
        }
        XCTAssertThrowsError(try LunaService.request(question: "q", recent: [], config: LunaConfiguration()))
    }

    func testStreamingPreservesUnicodeAndRequiresCompletion() throws {
        var decoder = LunaStreamDecoder()
        XCTAssertEqual(try decoder.receive(Data(#"{"type":"response.output_text.delta","delta":"Привет "}"#.utf8)), "Привет ")
        XCTAssertEqual(try decoder.receive(Data(#"{"type":"response.output_text.delta","delta":"🌙"}"#.utf8)), "Привет 🌙")
        XCTAssertThrowsError(try decoder.finish())
        _ = try decoder.receive(Data(#"{"type":"response.completed"}"#.utf8))
        XCTAssertEqual(try decoder.finish(), "Привет 🌙")
    }

    func testFailureDoesNotLookLikeFinishedAnswer() throws {
        var decoder = LunaStreamDecoder()
        _ = try decoder.receive(Data(#"{"type":"response.output_text.delta","delta":"Начало"}"#.utf8))
        XCTAssertThrowsError(try decoder.receive(Data(#"{"type":"response.failed"}"#.utf8)))
        XCTAssertEqual(decoder.text, "Начало")
        XCTAssertFalse(decoder.isComplete)
    }

    func testEmptyCompletionIsAnError() throws {
        var decoder = LunaStreamDecoder()
        _ = try decoder.receive(Data(#"{"type":"response.completed"}"#.utf8))
        XCTAssertThrowsError(try decoder.finish())
    }
}
