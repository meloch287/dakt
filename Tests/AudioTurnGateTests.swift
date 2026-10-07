import XCTest
@testable import DaktRecorder

final class AudioTurnGateTests: XCTestCase {
    func testQuestionEndsAfterShortSilenceWithoutWaitingForLongWindow() {
        var gate = AudioTurnGate()
        XCTAssertTrue(gate.append(level: 0.1, duration: 0.1, at: 1))
        XCTAssertFalse(gate.append(level: 0.1, duration: 0.1, at: 1.1))
        XCTAssertNil(gate.finishIfDue(at: 1.3))
        XCTAssertEqual(gate.finishIfDue(at: 1.51), true)
        XCTAssertFalse(gate.isRecording)
    }

    func testSilenceAndShortClicksAreNotSentToRecognition() {
        var gate = AudioTurnGate()
        XCTAssertFalse(gate.append(level: 0, duration: 1, at: 1))
        XCTAssertNil(gate.finishIfDue(at: 100))
        XCTAssertTrue(gate.append(level: 0.5, duration: 0.01, at: 101))
        XCTAssertEqual(gate.finishIfDue(at: 102), false)
    }

    func testLongContinuousAudioIsBounded() {
        var gate = AudioTurnGate()
        for frame in 0..<130 {
            _ = gate.append(level: 0.1, duration: 0.1, at: Double(frame) / 10)
        }
        XCTAssertEqual(gate.finishIfDue(at: 13), true)
    }

    func testMoreSpeechResetsSilenceDeadline() {
        var gate = AudioTurnGate()
        _ = gate.append(level: 0.1, duration: 0.2, at: 1)
        _ = gate.append(level: 0.1, duration: 0.2, at: 1.3)
        XCTAssertNil(gate.finishIfDue(at: 1.5))
        XCTAssertEqual(gate.finishIfDue(at: 1.71), true)
    }
}
