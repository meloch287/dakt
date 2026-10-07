import XCTest
@testable import DaktRecorder

final class SpeechFailureTests: XCTestCase {
    func testDisabledDictationIsNotTreatedAsScreenPermissionOrRetried() {
        let error = NSError(domain: "kLSRErrorDomain", code: 201,
                            userInfo: [NSLocalizedDescriptionKey: "Siri and Dictation are disabled"])
        let failure = SpeechFailure(error)
        XCTAssertEqual(failure.recovery, .dictation)
        XCTAssertFalse(failure.isRetryable)
        XCTAssertTrue(failure.localizedDescription.contains("Клавиатура"))
        XCTAssertFalse(failure.localizedDescription.contains("Разрешите запись экрана"))
    }

    func testWrappedDisabledDictationStillOffersKeyboardSettings() {
        let cause = NSError(domain: "kLSRErrorDomain", code: 201)
        let wrapper = NSError(domain: "kAFAssistantErrorDomain", code: 1101,
                              userInfo: [NSUnderlyingErrorKey: cause])
        XCTAssertEqual(SpeechFailure(wrapper).recovery, .dictation)
    }

    func testUnrelatedFailureDoesNotClaimDictationIsDisabled() {
        let failure = SpeechFailure(NSError(domain: "kAFAssistantErrorDomain", code: 1101,
                                            userInfo: [NSLocalizedDescriptionKey: "Connection interrupted"]))
        XCTAssertNil(failure.recovery)
        XCTAssertTrue(failure.isRetryable)
        XCTAssertFalse(failure.localizedDescription.contains("выключена диктовка"))
        XCTAssertTrue(failure.localizedDescription.contains("1101"))
    }

    func testRecoveryLinksPointToDifferentSystemSettings() {
        XCTAssertTrue(SystemRecovery.dictation.url.absoluteString.contains("Keyboard"))
        XCTAssertTrue(SystemRecovery.speechRecognition.url.absoluteString.contains("Privacy_SpeechRecognition"))
        XCTAssertTrue(SystemRecovery.screenRecording.url.absoluteString.contains("Privacy_ScreenCapture"))
    }

    @MainActor
    func testAnotherErrorClearsObsoletePermissionAction() async {
        let assistant = AssistantController(preferences: AssistantPreferences(preview: true), preview: true)
        assistant.reportSpeechFailure(SpeechFailure(NSError(domain: "kLSRErrorDomain", code: 201)))
        XCTAssertEqual(assistant.recovery, .dictation)
        assistant.error = "Прокси не отвечает"
        XCTAssertNil(assistant.recovery)
    }
}
