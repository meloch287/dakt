import Foundation
import AVFoundation

/// Распознавание одного временного фрагмента системного звука через WhisperX.
enum WhisperX {
    struct Config {
        var baseURL: String
        var email: String
        var password: String
        var language: String
        var isComplete: Bool {
            normalizedBase(baseURL) != nil && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        }
    }

    enum Failure: LocalizedError {
        case notConfigured, badURL(String), auth(String), server(String), rejected(String), noSpeech, timedOut
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Заполните адрес, почту и пароль WhisperX."
            case .badURL(let text): return "Неверный адрес WhisperX: \(text)"
            case .auth(let text): return "WhisperX не принял авторизацию: \(text)"
            case .server(let text): return "Ошибка WhisperX: \(text)"
            case .rejected(let text): return "Не удалось распознать фразу: \(text)"
            case .noSpeech: return "В фрагменте не нашлось речи."
            case .timedOut: return "WhisperX не ответил за отведённое время."
            }
        }
    }

    struct Segment {
        let start: Double
        let speaker: String
        let text: String
    }

    actor Session {
        private let config: Config
        private var client: Client?
        private var entering: Task<Client, Error>?
        private var generation = UUID()
        init(config: Config) { self.config = config }

        func ready() async throws -> Client {
            if let client { return client }
            if let entering { return try await entering.value }
            guard let base = normalizedBase(config.baseURL) else { throw Failure.badURL(config.baseURL) }
            let email = config.email, password = config.password
            let ticket = generation
            let task = Task { () throws -> Client in
                let fresh = Client(base: base)
                do {
                    try await fresh.login(email: email, password: password)
                    try Task.checkCancellation()
                    return fresh
                } catch {
                    fresh.close()
                    throw error
                }
            }
            entering = task
            defer { if generation == ticket { entering = nil } }
            let opened = try await task.value
            guard generation == ticket else { opened.close(); throw CancellationError() }
            client = opened
            return opened
        }

        func forget() {
            generation = UUID()
            entering?.cancel()
            entering = nil
            client?.close()
            client = nil
        }
    }

    static func transcribe(file: URL, config: Config, session: Session) async throws -> [Segment] {
        guard config.isComplete else { throw Failure.notConfigured }
        try Task.checkCancellation()
        let upload = try prepareUpload(file: file)
        defer { try? FileManager.default.removeItem(at: upload) }
        let client = try await session.ready()
        try Task.checkCancellation()
        let job = try await client.enqueue(file: upload, language: config.language, byChannel: false)
        try await client.wait(job: job) { _ in }
        try Task.checkCancellation()
        return try await client.result(job: job)
    }

    static func normalizedBase(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    /// Сервер требует не меньше 10 с. Дополняем короткую фразу тишиной до 11 с,
    /// а стереозвук складываем в моно: системный источник здесь всегда один.
    static func prepareUpload(file url: URL) throws -> URL {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw Failure.noSpeech }
        let rate = file.processingFormat.sampleRate
        let destination = url.deletingLastPathComponent().appendingPathComponent("whisper-upload-\(UUID().uuidString).m4a")
        var finished = false
        defer { if !finished { try? FileManager.default.removeItem(at: destination) } }
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 16_384),
              let scratch = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384),
              let sink = outputBuffer.floatChannelData?[0] else { throw Failure.rejected("не удалось подготовить аудиобуфер") }
        var writer: AVAudioFile? = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ])
        let total = max(file.length, AVAudioFramePosition(rate * 11))
        var position: AVAudioFramePosition = 0
        while position < total {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(min(16_384, total - position))
            outputBuffer.frameLength = frames
            memset(sink, 0, Int(frames) * MemoryLayout<Float>.size)
            if position < file.length {
                let count = AVAudioFrameCount(min(AVAudioFramePosition(frames), file.length - position))
                try file.read(into: scratch, frameCount: count)
                if let data = scratch.floatChannelData {
                    let channels = Int(file.processingFormat.channelCount)
                    for channel in 0..<channels {
                        for frame in 0..<Int(scratch.frameLength) {
                            sink[frame] += data[channel][frame] / Float(channels)
                        }
                    }
                }
            }
            try writer?.write(from: outputBuffer)
            position += AVAudioFramePosition(frames)
        }
        writer = nil
        finished = true
        return destination
    }
}
