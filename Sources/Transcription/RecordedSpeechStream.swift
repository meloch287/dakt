import Foundation
import AVFoundation

/// Диктофон для отдельных фраз: немного звука до начала речи, сама фраза,
/// 400 мс паузы — и сразу локальный разбор. Временный файл живёт только до
/// результата. Очередь ограничена текущим и последним ожидающим фрагментом.
final class RecordedSpeechStream: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dakt.speech.clips", qos: .userInitiated)
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dakt-clips-\(UUID().uuidString)")
    private let locale: String
    private let onDraft: (String) -> Void
    private let onUtterance: (String) -> Void
    private let onError: (String) -> Void
    private var gate = AudioTurnGate()
    private var writer: AVAudioFile?
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollDuration: TimeInterval = 0
    private var timer: DispatchSourceTimer?
    private var running = false
    private var processing: Task<Void, Never>?
    private var pending: URL?

    init(locale: String, onDraft: @escaping (String) -> Void,
         onUtterance: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.locale = locale
        self.onDraft = onDraft
        self.onUtterance = onUtterance
        self.onError = onError
    }

    func start() async throws {
        try await AudioClipTranscriber.prepare(locale: locale)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        queue.sync {
            running = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
            timer.setEventHandler { [weak self] in self?.finishIfDue() }
            self.timer = timer
            timer.resume()
        }
    }

    func append(_ audio: AVAudioPCMBuffer) {
        queue.async {
            guard self.running, audio.format.sampleRate > 0 else { return }
            let duration = Double(audio.frameLength) / audio.format.sampleRate
            let start = self.gate.append(level: audio.peakLevel, duration: duration, at: Date.timeIntervalSinceReferenceDate)
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
                    self.onDraft("Записываю фразу…")
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
            } catch { self.onError("Не удалось подготовить аудиофрагмент: \(error.localizedDescription)") }
        }
    }

    func stop() {
        let task: Task<Void, Never>? = queue.sync {
            running = false
            timer?.cancel()
            timer = nil
            writer = nil
            preRoll = []
            let active = processing
            active?.cancel()
            processing = nil
            pending = nil
            return active
        }
        let folder = self.folder
        Task {
            await task?.value
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func finishIfDue() {
        guard running, let useful = gate.finishIfDue(at: Date.timeIntervalSinceReferenceDate) else { return }
        let url = writer?.url
        writer = nil
        guard let url else { return }
        guard useful else { try? FileManager.default.removeItem(at: url); onDraft(""); return }
        if processing != nil {
            if let pending { try? FileManager.default.removeItem(at: pending) }
            pending = url
        } else { recognize(url) }
    }

    private func recognize(_ url: URL) {
        onDraft("Разбираю фразу…")
        processing = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let text = try await AudioClipTranscriber.recognize(file: url, locale: self.locale)
                try Task.checkCancellation()
                if !text.isEmpty { self.onUtterance(text) }
            } catch {
                if !Task.isCancelled { self.onError("Не удалось разобрать фразу: \(error.localizedDescription)") }
            }
            self.queue.async {
                self.processing = nil
                guard self.running else { return }
                if let next = self.pending {
                    self.pending = nil
                    self.recognize(next)
                } else { self.onDraft(self.gate.isRecording ? "Записываю фразу…" : "") }
            }
        }
    }
}
