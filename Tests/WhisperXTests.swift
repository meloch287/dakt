import XCTest
import AVFoundation
@testable import DaktRecorder

final class WhisperXTests: XCTestCase {
    @MainActor
    func testFreshSetupDoesNotSelectAPrivateWhisperServer() {
        let preferences = AssistantPreferences(preview: true)
        XCTAssertTrue(preferences.whisperURL.isEmpty)
        XCTAssertFalse(preferences.whisperConfiguration.isComplete)
    }

    // MARK: - Адрес сервиса

    func testNormalizedBaseAddsSchemeAndStripsSlash() {
        XCTAssertEqual(WhisperX.normalizedBase("203.0.113.10/")?.absoluteString, "https://203.0.113.10")
        XCTAssertEqual(WhisperX.normalizedBase("  http://host:8080///  ")?.absoluteString, "http://host:8080")
        XCTAssertEqual(WhisperX.normalizedBase("https://whisperx.example")?.absoluteString, "https://whisperx.example")
    }

    func testNormalizedBaseRejectsGarbage() {
        XCTAssertNil(WhisperX.normalizedBase(""))
        XCTAssertNil(WhisperX.normalizedBase("   "))
        XCTAssertNil(WhisperX.normalizedBase("https://"))
    }

    func testConfigCompleteness() {
        var config = WhisperX.Config(baseURL: "https://x", email: "a@b", password: "p", language: "ru")
        XCTAssertTrue(config.isComplete)
        config.password = ""
        XCTAssertFalse(config.isComplete)
    }

    // MARK: - Разбор ответа

    func testParseSegmentsReadsUtterancesWithSpeaker() throws {
        let json = """
        {"utterances":[
          {"start": 1.5, "end": 3.0, "text": " Привет ", "speaker": "SPEAKER_00"},
          {"start": "4", "end": 5, "text": "", "speaker": "SPEAKER_01"},
          {"start": 6, "transcription": "Ответ", "channel": 1}
        ]}
        """
        let segments = try XCTUnwrap(WhisperX.parseSegments(Data(json.utf8)))
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].start, 1.5)
        XCTAssertEqual(segments[0].text, "Привет")
        XCTAssertEqual(segments[0].speaker, "SPEAKER_00")
        XCTAssertEqual(segments[1].start, 6)
        XCTAssertEqual(segments[1].speaker, "1")
    }

    func testParseSegmentsFallsBackToSegmentsKey() throws {
        let json = #"{"segments":[{"start":0,"text":"a"}]}"#
        let segments = try XCTUnwrap(WhisperX.parseSegments(Data(json.utf8)))
        XCTAssertEqual(segments.map(\.text), ["a"])
        XCTAssertEqual(segments[0].speaker, "")
    }

    func testParseSegmentsNilOnNonJSON() {
        XCTAssertNil(WhisperX.parseSegments(Data("<html>".utf8)))
        XCTAssertNil(WhisperX.parseSegments(Data("[1,2]".utf8)))
    }

    func testUploadIsMonoAndShortSpeechIsPaddedToElevenSeconds() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("speech.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        var writer: AVAudioFile? = try AVAudioFile(forWriting: input, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        for index in 0..<4_800 {
            buffer.floatChannelData![0][index] = 0
            buffer.floatChannelData![1][index] = 0.4 * sin(Float(index) * 2 * .pi * 440 / 48_000)
        }
        try writer?.write(from: buffer)
        writer = nil
        let output = try WhisperX.prepareUpload(file: input)
        let file = try AVAudioFile(forReading: output)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 11, accuracy: 0.1)
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800))
        try file.read(into: decoded)
        XCTAssertGreaterThan(decoded.peakLevel, 0.1, "Правый канал тоже должен попасть в распознавание")
    }
}
