import Combine
import XCTest
@testable import DaktRecorder

final class AudioActivityTests: XCTestCase {
    @MainActor
    func testHiddenMeterKeepsLatestValueWithoutPublishingUntilShown() {
        let activity = AudioActivity()
        activity.setVisible(false)
        var changes = 0
        let observation = activity.objectWillChange.sink { changes += 1 }
        for index in 0..<100 { activity.level = Float(index) / 100 }
        XCTAssertEqual(changes, 0)
        activity.setVisible(true)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(activity.level, 0.99, accuracy: 0.001)
        activity.level = 0
        XCTAssertEqual(changes, 2)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testIdenticalSilenceDoesNotInvalidateTheMeter() {
        let activity = AudioActivity()
        var changes = 0
        let observation = activity.objectWillChange.sink { changes += 1 }
        for _ in 0..<100 { activity.level = 0 }
        XCTAssertEqual(changes, 0)
        withExtendedLifetime(observation) {}
    }
}
