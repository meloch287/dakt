import XCTest
@testable import DaktRecorder

final class AudioTurnGateTests: XCTestCase {
    func testOneSecondPauseDoesNotCutAQuestionByDefault() {
        var gate = AudioTurnGate()
        _ = gate.append(level: 0.1, duration: 0.3, at: 1)
        XCTAssertNil(gate.finishIfDue(at: 2))
        XCTAssertFalse(gate.append(level: 0.1, duration: 0.1, at: 2.05))
        XCTAssertNil(gate.finishIfDue(at: 3.05))
        XCTAssertEqual(gate.finishIfDue(at: 3.3), .init(shouldTranscribe: true, endsTurn: true))
    }

    func testConfiguredFastPauseRemainsAvailableAndSurvivesReset() {
        var gate = AudioTurnGate(silence: 0.4)
        for start in [1.0, 4.0] {
            _ = gate.append(level: 0.1, duration: 0.2, at: start)
            XCTAssertNil(gate.finishIfDue(at: start + 0.3))
            XCTAssertEqual(gate.finishIfDue(at: start + 0.5), .init(shouldTranscribe: true, endsTurn: true))
        }
    }

    func testSilenceAndShortClicksAreNotTranscribed() {
        var gate = AudioTurnGate()
        XCTAssertFalse(gate.append(level: 0, duration: 1, at: 1))
        XCTAssertNil(gate.finishIfDue(at: 100))
        _ = gate.append(level: 0.5, duration: 0.01, at: 101)
        XCTAssertEqual(gate.finishIfDue(at: 102.3), .init(shouldTranscribe: false, endsTurn: true))
        XCTAssertNil(gate.finishIfDue(at: 104))
    }

    func testLongAudioIsSplitWithoutEndingTheQuestion() {
        var gate = AudioTurnGate()
        for frame in 1...120 {
            _ = gate.append(level: 0.1, duration: 0.1, at: Double(frame) / 10)
        }
        XCTAssertEqual(gate.finishIfDue(at: 12), .init(shouldTranscribe: true, endsTurn: false))
        XCTAssertFalse(gate.isRecording)
        XCTAssertTrue(gate.hasOpenTurn)
        _ = gate.append(level: 0.1, duration: 0.1, at: 12.1)
        XCTAssertNil(gate.finishIfDue(at: 13.1))
        XCTAssertEqual(gate.finishIfDue(at: 13.4), .init(shouldTranscribe: true, endsTurn: true))
    }

    func testSilenceRightAfterTheLengthLimitStillClosesTheQuestion() {
        var gate = AudioTurnGate()
        for frame in 1...120 {
            _ = gate.append(level: 0.1, duration: 0.1, at: Double(frame) / 10)
        }
        XCTAssertEqual(gate.finishIfDue(at: 12), .init(shouldTranscribe: true, endsTurn: false))
        XCTAssertEqual(gate.finishIfDue(at: 13.3), .init(shouldTranscribe: false, endsTurn: true))
        XCTAssertFalse(gate.hasOpenTurn)
        XCTAssertNil(gate.finishIfDue(at: 14))
    }

    func testMoreSpeechResetsThePauseDeadline() {
        var gate = AudioTurnGate()
        _ = gate.append(level: 0.1, duration: 0.2, at: 1)
        _ = gate.append(level: 0.1, duration: 0.2, at: 2)
        XCTAssertNil(gate.finishIfDue(at: 3))
        XCTAssertEqual(gate.finishIfDue(at: 3.3), .init(shouldTranscribe: true, endsTurn: true))
    }
}
