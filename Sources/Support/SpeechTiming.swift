import Foundation

enum SpeechTiming {
    static let defaultPause: TimeInterval = 1.2
    static let pauseRange: ClosedRange<TimeInterval> = 0.4...2.5

    static func normalized(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultPause }
        return min(pauseRange.upperBound, max(pauseRange.lowerBound, value))
    }
}
