import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// Захватывает весь системный звук. Нет AVAudioEngine, доступа к микрофону
/// или файлов записи; единственный выход — буфер для распознавания.
final class SystemAudioListener: NSObject, SCStreamOutput, SCStreamDelegate {
    private let audioQueue = DispatchQueue(label: "dakt.system.audio", qos: .userInitiated)
    private let screenQueue = DispatchQueue(label: "dakt.system.frames", qos: .utility)
    private let lock = NSLock()
    private var active = false
    private var stream: SCStream?
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private let onLevel: (Float) -> Void
    private let onError: (String) -> Void
    private var lastMeter = Date.distantPast

    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
         onLevel: @escaping (Float) -> Void,
         onError: @escaping (String) -> Void) {
        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.onError = onError
    }

    func start() async throws {
        let content: SCShareableContent = try await withCheckedThrowingContinuation { continuation in
            let gate = CallbackGate(continuation)
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
                if let content { gate.finish(.success(content)) }
                else { gate.finish(.failure(error ?? RecorderError.message("Не удалось получить системный звук."))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                gate.finish(.failure(RecorderError.message("Разрешите Dakt запись экрана и системного звука в настройках macOS, затем перезапустите приложение.")))
            }
        }
        try Task.checkCancellation()
        guard let display = content.displays.first else { throw RecorderError.message("Не найден экран для захвата системного звука.") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // ScreenCaptureKit требует видеоконфигурацию, но кадры не читаем и не сохраняем.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        lock.withLock { active = true }
        self.stream = stream
        do { try await stream.startCapture() }
        catch {
            lock.withLock { active = false }
            self.stream = nil
            throw error
        }
    }

    func stop() async {
        lock.withLock { active = false }
        let previous = stream
        stream = nil
        try? await previous?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, lock.withLock({ active }), CMSampleBufferDataIsReady(buffer),
              let description = CMSampleBufferGetFormatDescription(buffer),
              var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let format = AVAudioFormat(streamDescription: &asbd) else { return }
        try? buffer.withAudioBufferList { list, _ in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer),
                  let copy = pcm.deepCopy() else { return }
            onBuffer(copy)
            if Date().timeIntervalSince(lastMeter) >= 0.1 {
                lastMeter = Date()
                onLevel(copy.peakLevel)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let wasActive = lock.withLock { () -> Bool in
            let value = active
            active = false
            return value
        }
        if wasActive { onError("Системный звук прервался: \(error.localizedDescription)") }
    }
}

/// Тайм-аут не ждёт завершения системного API, который может игнорировать
/// отмену. Опоздавший callback не возобновляет continuation второй раз.
final class CallbackGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}

/// Аудиопоток не обращается к состоянию SwiftUI. На остановке маршрут
/// обнуляется прежде, чем закрываются захват и распознаватель.
final class AudioBufferRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    func route(to sink: ((AVAudioPCMBuffer) -> Void)?) { lock.withLock { self.sink = sink } }
    func feed(_ buffer: AVAudioPCMBuffer) { lock.withLock { sink }?(buffer) }
}
