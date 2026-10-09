import Foundation
import AVFoundation

/// Файлы ограничены по длине, но вопрос заканчивается только после паузы.
/// Все части распознаются по порядку, включая пустую финальную границу.
final class RecordedSpeechStream: @unchecked Sendable {
    typealias Prepare = (String) async throws -> Void
    typealias Transcribe = (URL, String) async throws -> String
    private struct Part {
        let file: URL?
        let endsTurn: Bool
    }
    private let queue = DispatchQueue(label: "dakt.speech.clips", qos: .userInitiated)
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dakt-clips-\(UUID().uuidString)")
    private let locale: String
    private let prepare: Prepare
    private let transcribe: Transcribe
    private let now: @Sendable () -> TimeInterval
    private let onDraft: (String) -> Void
    private let onUtterance: (String) -> Void
    private let onError: (String) -> Void
    private var gate: AudioTurnGate
    private var turn = SpeechTurnBuffer()
    private var writer: AVAudioFile?
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollDuration: TimeInterval = 0
    private var timer: DispatchSourceTimer?
    private var timerDeadline: TimeInterval?
    private var running = false
    private var generation = UUID()
    private var processing: Task<Void, Never>?
    private var pending: [Part] = []
    private static let maximumPendingParts = 8

    init(locale: String, pause: TimeInterval = SpeechTiming.defaultPause,
         prepare: @escaping Prepare = { try await AudioClipTranscriber.prepare(locale: $0) },
         transcribe: @escaping Transcribe = { try await AudioClipTranscriber.recognize(file: $0, locale: $1) },
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         onDraft: @escaping (String) -> Void,
         onUtterance: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.locale = locale
        self.prepare = prepare
        self.transcribe = transcribe
        self.now = now
        self.onDraft = onDraft
        self.onUtterance = onUtterance
        self.onError = onError
        gate = AudioTurnGate(silence: pause)
    }

    func start() async throws {
        try await prepare(locale)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        queue.sync {
            running = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .distantFuture)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.timerDeadline = nil
                self.finishIfDue(at: self.now())
                self.scheduleBoundary()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func append(_ audio: AVAudioPCMBuffer) {
        let timestamp = now()
        queue.async {
            guard self.running, audio.format.sampleRate > 0 else { return }
            let duration = Double(audio.frameLength) / audio.format.sampleRate
            let start = self.gate.append(level: audio.peakLevel, duration: duration, at: timestamp)
            do {
                if start {
                    var settings = audio.format.settings
                    settings[AVLinearPCMIsNonInterleaved] = false
                    self.writer = try AVAudioFile(forWriting: self.folder.appendingPathComponent("\(UUID().uuidString).caf"),
                                                  settings: settings, commonFormat: audio.format.commonFormat,
                                                  interleaved: audio.format.isInterleaved)
                    for buffered in self.preRoll where buffered.format == audio.format { try self.writer?.write(from: buffered) }
                    self.preRoll = []
                    self.preRollDuration = 0
                    self.onDraft("Записываю вопрос…")
                }
                if let writer = self.writer { try writer.write(from: audio) }
                else {
                    self.preRoll.append(audio)
                    self.preRollDuration += duration
                    while self.preRollDuration > 0.25, !self.preRoll.isEmpty {
                        let removed = self.preRoll.removeFirst()
                        self.preRollDuration -= Double(removed.frameLength) / removed.format.sampleRate
                    }
                }
                self.finishIfDue(at: timestamp)
                self.scheduleBoundary()
            } catch { self.fail("Не удалось подготовить аудиофрагмент: \(error.localizedDescription)") }
        }
    }

    /// Барьер для диагностик и детерминированной подачи синтетического звука.
    func flushAudio() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    func stop() {
        let task: Task<Void, Never>? = queue.sync {
            running = false
            generation = UUID()
            timer?.cancel()
            timer = nil
            timerDeadline = nil
            writer = nil
            preRoll = []
            preRollDuration = 0
            turn.reset()
            let active = processing
            active?.cancel()
            processing = nil
            pending = []
            return active
        }
        let folder = self.folder
        Task {
            await task?.value
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func finishIfDue(at timestamp: TimeInterval) {
        guard running, let boundary = gate.finishIfDue(at: timestamp) else { return }
        let file = writer?.url
        writer = nil
        if boundary.shouldTranscribe, let file {
            enqueue(Part(file: file, endsTurn: boundary.endsTurn))
        } else {
            if let file { try? FileManager.default.removeItem(at: file) }
            if boundary.endsTurn { enqueue(Part(file: nil, endsTurn: true)) }
        }
    }

    /// Нет периодического опроса в тишине. Пока речь сдвигает границу вперёд,
    /// оставляем ранний таймер: он один раз проверит новую дату и уснёт снова.
    /// Это также завершает вопрос, если захват перестал присылать буферы тишины.
    private func scheduleBoundary() {
        guard running, let timer else { return }
        guard let deadline = gate.nextDeadline else {
            if timerDeadline != nil { timer.schedule(deadline: .distantFuture) }
            timerDeadline = nil
            return
        }
        if let scheduled = timerDeadline, scheduled <= deadline { return }
        timerDeadline = deadline
        timer.schedule(deadline: .now() + max(0, deadline - now()), leeway: .milliseconds(10))
    }

    private func enqueue(_ part: Part) {
        guard pending.count < Self.maximumPendingParts else {
            if let file = part.file { try? FileManager.default.removeItem(at: file) }
            fail("Распознавание не успевает обрабатывать звук. Повторите запуск прослушивания.")
            return
        }
        pending.append(part)
        processNext()
    }

    private func processNext() {
        guard running, processing == nil else { return }
        while !pending.isEmpty {
            let part = pending.removeFirst()
            guard let file = part.file else {
                publish("", endsTurn: part.endsTurn)
                continue
            }
            let ticket = generation
            onDraft(gate.isRecording ? "Записываю вопрос…" : "Разбираю вопрос…")
            processing = Task { [weak self] in
                guard let self else { return }
                let result: Result<String, Error>
                do {
                    let text = try await self.transcribe(file, self.locale)
                    try Task.checkCancellation()
                    result = .success(text)
                } catch { result = .failure(error) }
                // После окончания анализа файл больше не используется.
                try? FileManager.default.removeItem(at: file)
                self.queue.async {
                    guard self.running, self.generation == ticket else { return }
                    self.processing = nil
                    switch result {
                    case .success(let text):
                        self.publish(text, endsTurn: part.endsTurn)
                        self.processNext()
                    case .failure(let error):
                        self.fail("Не удалось разобрать вопрос: \(error.localizedDescription)")
                    }
                }
            }
            return
        }
        onDraft(gate.isRecording ? "Записываю вопрос…" : (gate.hasOpenTurn ? "Слушаю продолжение вопроса…" : ""))
    }

    private func publish(_ text: String, endsTurn: Bool) {
        if let completed = turn.append(text, endsTurn: endsTurn) { onUtterance(completed) }
    }

    private func fail(_ message: String) {
        guard running else { return }
        running = false
        generation = UUID()
        timer?.cancel()
        timer = nil
        timerDeadline = nil
        writer = nil
        processing?.cancel()
        for part in pending {
            if let file = part.file { try? FileManager.default.removeItem(at: file) }
        }
        pending = []
        turn.reset()
        onError(message)
    }
}
