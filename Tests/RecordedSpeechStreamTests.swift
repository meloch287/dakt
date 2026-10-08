import AVFoundation
import XCTest
@testable import DaktRecorder

final class RecordedSpeechStreamTests: XCTestCase {
    @MainActor
    func testStalledRecognitionReportsOverloadInsteadOfSilentlyDroppingAudio() async throws {
        let clock = SpeechTestClock()
        let first = expectation(description: "first started")
        let overload = expectation(description: "overload reported")
        let probe = ClipRecognitionProbe(holdFirst: true, onFirst: { first.fulfill() })
        let stream = makeStream(clock: clock, probe: probe, onError: { message in
            XCTAssertTrue(message.contains("не успевает"))
            overload.fulfill()
        }) { _ in XCTFail("Stopped queue must not emit partial questions") }
        try await stream.start()
        defer { stream.stop() }
        await feed(3, level: 0.1, stream: stream, clock: clock)
        await feed(14, level: 0, stream: stream, clock: clock)
        await fulfillment(of: [first], timeout: 3)
        for _ in 0..<12 {
            await feed(3, level: 0.2, stream: stream, clock: clock)
            await feed(14, level: 0, stream: stream, clock: clock)
        }
        await fulfillment(of: [overload], timeout: 3)
        await probe.releaseFirst()
        await stream.flushAudio()
        let count = await probe.files.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testOneSecondPauseStaysInsideOneQuestion() async throws {
        let clock = SpeechTestClock()
        let probe = ClipRecognitionProbe()
        let received = expectation(description: "whole question")
        let sink = SpeechTextSink()
        let stream = makeStream(clock: clock, probe: probe) { text in sink.append(text); received.fulfill() }
        try await stream.start()
        defer { stream.stop() }
        await feed(3, level: 0.1, stream: stream, clock: clock)
        await feed(10, level: 0, stream: stream, clock: clock)
        XCTAssertTrue(sink.values.isEmpty)
        await feed(3, level: 0.1, stream: stream, clock: clock)
        await feed(14, level: 0, stream: stream, clock: clock)
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(sink.values, ["Вопрос 1?"])
        let files = await probe.files
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path))
    }

    @MainActor
    func testBusyRecognitionKeepsAllPendingAudioInOrder() async throws {
        let clock = SpeechTestClock()
        let first = expectation(description: "first recognition started")
        let probe = ClipRecognitionProbe(holdFirst: true, onFirst: { first.fulfill() })
        let received = expectation(description: "three ordered questions")
        received.expectedFulfillmentCount = 3
        let sink = SpeechTextSink()
        let stream = makeStream(clock: clock, probe: probe) { text in sink.append(text); received.fulfill() }
        try await stream.start()
        defer { stream.stop() }
        await feed(3, level: 0.1, stream: stream, clock: clock)
        await feed(14, level: 0, stream: stream, clock: clock)
        await fulfillment(of: [first], timeout: 3)
        for level: Float in [0.2, 0.3] {
            await feed(3, level: level, stream: stream, clock: clock)
            await feed(14, level: 0, stream: stream, clock: clock)
        }
        XCTAssertTrue(sink.values.isEmpty)
        await probe.releaseFirst()
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(sink.values, ["Вопрос 1?", "Вопрос 2?", "Вопрос 3?"])
        let count = await probe.files.count
        XCTAssertEqual(count, 3)
    }

    @MainActor
    func testQuestionSpanningTwoFilesIsDeliveredOnce() async throws {
        let clock = SpeechTestClock()
        let probe = ClipRecognitionProbe()
        let received = expectation(description: "one long question")
        let sink = SpeechTextSink()
        let stream = makeStream(clock: clock, probe: probe) { text in sink.append(text); received.fulfill() }
        try await stream.start()
        defer { stream.stop() }
        await feed(120, level: 0.1, stream: stream, clock: clock)
        XCTAssertTrue(sink.values.isEmpty)
        await feed(5, level: 0.2, stream: stream, clock: clock)
        await feed(14, level: 0, stream: stream, clock: clock)
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(sink.values, ["Вопрос 1? Вопрос 2?"])
        let count = await probe.files.count
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testSilenceAfterAFullFileClosesTheTurnWithoutAnotherRecording() async throws {
        let clock = SpeechTestClock()
        let first = expectation(description: "first started")
        let probe = ClipRecognitionProbe(holdFirst: true, onFirst: { first.fulfill() })
        let received = expectation(description: "full question")
        let sink = SpeechTextSink()
        let stream = makeStream(clock: clock, probe: probe) { text in sink.append(text); received.fulfill() }
        try await stream.start()
        defer { stream.stop() }
        await feed(120, level: 0.1, stream: stream, clock: clock)
        await fulfillment(of: [first], timeout: 3)
        await feed(14, level: 0, stream: stream, clock: clock)
        await probe.releaseFirst()
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(sink.values, ["Вопрос 1?"])
        let count = await probe.files.count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testStoppingDiscardsPendingAndLateRecognition() async throws {
        let clock = SpeechTestClock()
        let first = expectation(description: "first started")
        let probe = ClipRecognitionProbe(holdFirst: true, onFirst: { first.fulfill() })
        let unexpected = expectation(description: "no speech after stopping")
        unexpected.isInverted = true
        let stream = makeStream(clock: clock, probe: probe) { _ in unexpected.fulfill() }
        try await stream.start()
        await feed(3, level: 0.1, stream: stream, clock: clock)
        await feed(14, level: 0, stream: stream, clock: clock)
        await fulfillment(of: [first], timeout: 3)
        await feed(3, level: 0.2, stream: stream, clock: clock)
        await feed(14, level: 0, stream: stream, clock: clock)
        stream.stop()
        await probe.releaseFirst()
        await fulfillment(of: [unexpected], timeout: 0.2)
        let count = await probe.files.count
        XCTAssertEqual(count, 1)
    }

    private func makeStream(clock: SpeechTestClock, probe: ClipRecognitionProbe,
                            onError: @escaping (String) -> Void = { XCTFail($0) },
                            receive: @escaping (String) -> Void) -> RecordedSpeechStream {
        RecordedSpeechStream(locale: "ru-RU", prepare: { _ in },
                             transcribe: { file, _ in try await probe.recognize(file) },
                             now: { clock.time }, onDraft: { _ in },
                             onUtterance: receive, onError: onError)
    }

    @MainActor
    private func feed(_ frames: Int, level: Float, stream: RecordedSpeechStream, clock: SpeechTestClock) async {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        for _ in 0..<frames {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
            buffer.frameLength = 1_600
            buffer.floatChannelData![0].update(repeating: level, count: 1_600)
            clock.advance()
            stream.append(buffer)
            await stream.flushAudio()
        }
    }
}

private final class SpeechTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks = 0
    var time: TimeInterval { lock.withLock { Double(ticks) / 10 } }
    func advance() { lock.withLock { ticks += 1 } }
}

private final class SpeechTextSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var values: [String] { lock.withLock { stored } }
    func append(_ value: String) { lock.withLock { stored.append(value) } }
}

private actor ClipRecognitionProbe {
    private let holdFirst: Bool
    private let onFirst: @Sendable () -> Void
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var files: [URL] = []

    init(holdFirst: Bool = false, onFirst: @escaping @Sendable () -> Void = {}) {
        self.holdFirst = holdFirst
        self.onFirst = onFirst
    }

    func recognize(_ file: URL) async throws -> String {
        let first = files.isEmpty
        files.append(file)
        let audio = try AVAudioFile(forReading: file)
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
        try audio.read(into: buffer)
        let value = Int((buffer.peakLevel * 10).rounded())
        if first {
            onFirst()
            if holdFirst && !released { await withCheckedContinuation { waiter = $0 } }
        }
        return "Вопрос \(value)?"
    }

    func releaseFirst() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
