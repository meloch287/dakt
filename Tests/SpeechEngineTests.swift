import XCTest
@testable import DaktRecorder

final class SpeechEngineTests: XCTestCase {
    @MainActor
    func testOnlyBuiltInSpeechEnginesAreOffered() {
        XCTAssertEqual(AssistantPreferences.SpeechEngine.allCases.map(\.rawValue), ["clips", "apple"])
    }

    @MainActor
    func testRemovedEngineFallsBackToFastClipsWhenSupported() {
        XCTAssertEqual(AssistantPreferences.SpeechEngine.restore("retired-engine", supportsClips: true), .clips)
    }

    @MainActor
    func testOlderMacFallsBackToAppleSpeech() {
        XCTAssertEqual(AssistantPreferences.SpeechEngine.restore("retired-engine", supportsClips: false), .apple)
        XCTAssertEqual(AssistantPreferences.SpeechEngine.restore("clips", supportsClips: false), .apple)
    }

    @MainActor
    func testExplicitAppleSelectionIsPreserved() {
        XCTAssertEqual(AssistantPreferences.SpeechEngine.restore("apple", supportsClips: true), .apple)
    }

}
