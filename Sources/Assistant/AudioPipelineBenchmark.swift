#if DEBUG
import Foundation

/// Явный диагностический запуск с указанным файлом. Не захватывает разговор.
enum AudioPipelineBenchmark {
    static func run(file: URL) async throws {
        let config = try CorporateProxyProfile.load()
        let preparing = Date()
        try await AudioClipTranscriber.prepare(locale: "ru-RU")
        try await AudioClipTranscriber.prepare(locale: "ru-RU")
        print("prepare_seconds=\(Date().timeIntervalSince(preparing))")
        for run in 1...3 {
            let start = Date()
            let text = try await AudioClipTranscriber.recognize(file: file, locale: "ru-RU")
            guard !text.isEmpty else { throw RecorderError.message("Тестовый звук не распознан.") }
            let decoded = Date().timeIntervalSince(start)
            let first = FirstAnswerTime(start: start)
            let answer = try await LunaService.answer(question: text, recent: [], config: config) { _ in first.receive() }
            let result: [String: Any] = [
                "run": run, "model": LunaConfiguration.model,
                "audio_decode_s": decoded,
                "first_answer_s": first.seconds ?? 0,
                "total_s": Date().timeIntervalSince(start),
                "transcript": text, "answer": answer,
                "note": "После завершения записи; пауза определения конца фразы 0.4 с сюда не входит."
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        }
    }

    private final class FirstAnswerTime: @unchecked Sendable {
        let start: Date
        private let lock = NSLock()
        private var value: TimeInterval?
        init(start: Date) { self.start = start }
        func receive() { lock.withLock { if value == nil { value = Date().timeIntervalSince(start) } } }
        var seconds: TimeInterval? { lock.withLock { value } }
    }
}
#endif
