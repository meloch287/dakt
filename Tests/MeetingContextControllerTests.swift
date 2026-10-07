import XCTest
@testable import DaktRecorder

final class MeetingContextControllerTests: XCTestCase {
    @MainActor
    private func preferences() -> AssistantPreferences {
        let preferences = AssistantPreferences(preview: true)
        preferences.apiKey = "test"
        preferences.resumeText = "Кандидат: Python backend, FastAPI, PostgreSQL."
        preferences.context = "Предыдущий контекст"
        return preferences
    }

    @MainActor
    func testManualEditsAreNotOverwrittenAndApplyingCanBeUndone() async {
        let preferences = preferences()
        let started = expectation(description: "generation started")
        var pending: CheckedContinuation<String, Never>?
        let editor = MeetingContextController(preferences: preferences) { _, _, _ in
            await withCheckedContinuation { continuation in pending = continuation; started.fulfill() }
        }
        editor.generate()
        await fulfillment(of: [started], timeout: 2)
        preferences.context = "Мои новые заметки"
        pending?.resume(returning: "Шаблон по резюме")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(preferences.context, "Мои новые заметки")
        XCTAssertTrue(editor.requiresApply)
        editor.applyDraft()
        XCTAssertEqual(preferences.context, "Шаблон по резюме")
        editor.restorePrevious()
        XCTAssertEqual(preferences.context, "Мои новые заметки")
    }

    @MainActor
    func testOldResumeResultIsDiscardedAfterSourceChanges() async {
        let preferences = preferences()
        let started = expectation(description: "generation started")
        var pending: CheckedContinuation<String, Never>?
        let editor = MeetingContextController(preferences: preferences) { _, _, _ in
            await withCheckedContinuation { continuation in pending = continuation; started.fulfill() }
        }
        editor.generate()
        await fulfillment(of: [started], timeout: 2)
        preferences.resumeText = "Новый кандидат: Swift."
        pending?.resume(returning: "Старые факты Python")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(preferences.context, "Предыдущий контекст")
        XCTAssertTrue(editor.draft.isEmpty)
        XCTAssertFalse(editor.isGenerating)
    }

    @MainActor
    func testPasteGeneratesAndAppliesTemplateAutomatically() async {
        let preferences = preferences()
        let requested = expectation(description: "new resume used")
        let editor = MeetingContextController(preferences: preferences) { _, config, _ in
            XCTAssertEqual(config.resume, "Новый опыт Python и речевые технологии.")
            requested.fulfill()
            return "Готовый шаблон"
        }
        editor.importText("Новый опыт Python и речевые технологии.")
        await fulfillment(of: [requested], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(preferences.context, "Готовый шаблон")
        XCTAssertEqual(preferences.resumeName, "Текст из буфера")
    }

    @MainActor
    func testFailureKeepsResumeAndExistingContext() async {
        let preferences = preferences()
        let requested = expectation(description: "failed request")
        let editor = MeetingContextController(preferences: preferences) { _, _, _ in
            requested.fulfill()
            throw RecorderError.message("Сеть недоступна")
        }
        editor.generate()
        await fulfillment(of: [requested], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(preferences.context, "Предыдущий контекст")
        XCTAssertTrue(preferences.resumeText.contains("Python"))
        XCTAssertNotNil(editor.error)
        XCTAssertFalse(editor.isBusy)
    }
}
