import XCTest
@testable import DaktRecorder

final class AudioPromptTests: XCTestCase {
    @MainActor
    func testRecordingStatusCannotBeSentAsAQuestion() async {
        let preferences = AssistantPreferences(preview: true)
        preferences.engine = .clips
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.receiveDraft("Записываю фразу…")
        XCTAssertEqual(assistant.captureStatus, "Записываю фразу…")
        XCTAssertTrue(assistant.draft.isEmpty)
        XCTAssertFalse(assistant.canAnswerLatest)
        assistant.receive("Как это работает?")
        XCTAssertTrue(assistant.canAnswerLatest)
    }

    @MainActor
    func testRealStreamingDraftCanBeAnsweredManually() async {
        let preferences = AssistantPreferences(preview: true)
        preferences.engine = .apple
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.receiveDraft("Как это работает")
        XCTAssertEqual(assistant.draft, "Как это работает")
        XCTAssertTrue(assistant.canAnswerLatest)
        XCTAssertTrue(assistant.captureStatus.isEmpty)
    }
}
