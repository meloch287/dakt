import AVFoundation
import XCTest
@testable import DaktRecorder

final class AudioFormatTests: XCTestCase {
    func testCopyOwnsItsMemoryAfterCaptureReusesSource() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let original = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        original.frameLength = 4
        for channel in 0..<2 {
            for index in 0..<4 { original.floatChannelData![channel][index] = 0.5 }
        }
        let copy = try XCTUnwrap(original.deepCopy())
        original.floatChannelData![0][0] = 0
        XCTAssertEqual(copy.floatChannelData![0][0], 0.5)
        XCTAssertEqual(copy.frameLength, 4)
    }

    func testPeakReadsEveryInterleavedSample() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true))
        let audio = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        audio.frameLength = 3
        let values: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, -0.9]
        for index in values.indices { audio.floatChannelData![0][index] = values[index] }
        XCTAssertEqual(audio.peakLevel, 0.9, accuracy: 0.001)
    }
}
