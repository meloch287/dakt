import AVFoundation

/// Запасной движок: короткие окна только системной дорожки во временной
/// папке. Одновременно обрабатываются максимум два окна, очередь ограничена.
final class WhisperSpeechStream: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dakt.speech.whisper", qos: .userInitiated)
    private let config: WhisperX.Config
    private let session: WhisperX.Session
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dakt-speech-\(UUID().uuidString)")
    private let onDraft: (String) -> Void
    private let onUtterance: (String) -> Void
    private let onError: (String) -> Void
    private var writer: AVAudioFile?
    private var timer: DispatchSourceTimer?
    private var opened = Date()
    private var lastVoice = Date.distantPast
    private var hasSpeech = false
    private var running = false
    private var sequence = 0
    private var nextToShow = 0
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var ready: [Int: String] = [:]

    init(config: WhisperX.Config, onDraft: @escaping (String) -> Void,
         onUtterance: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.config = config
        session = WhisperX.Session(config: config)
        self.onDraft = onDraft
        self.onUtterance = onUtterance
        self.onError = onError
    }

    func start() throws {
        guard config.isComplete else { throw RecorderError.message("Заполните адрес, почту и пароль WhisperX.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        queue.sync {
            running = true
            opened = Date()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.15, repeating: 0.15)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func append(_ audio: AVAudioPCMBuffer) {
        queue.async {
            guard self.running else { return }
            if audio.peakLevel > 0.01 { self.lastVoice = Date(); self.hasSpeech = true }
            do {
                if self.writer == nil {
                    var settings = audio.format.settings
                    settings[AVLinearPCMIsNonInterleaved] = false
                    self.writer = try AVAudioFile(forWriting: self.folder.appendingPathComponent("\(UUID().uuidString).caf"),
                                                  settings: settings, commonFormat: audio.format.commonFormat,
                                                  interleaved: audio.format.isInterleaved)
                }
                try self.writer?.write(from: audio)
            } catch { self.onError("Не удалось подготовить звук для WhisperX: \(error.localizedDescription)") }
        }
    }

    func stop() {
        let pending: [Task<Void, Never>] = queue.sync {
            running = false
            timer?.cancel()
            timer = nil
            writer = nil
            let pending = Array(tasks.values)
            pending.forEach { $0.cancel() }
            tasks = [:]
            ready = [:]
            return pending
        }
        let folder = self.folder, session = self.session
        Task {
            await session.forget()
            for task in pending { await task.value }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func tick() {
        guard running else { return }
        let duration = Date().timeIntervalSince(opened)
        let ended = hasSpeech && duration >= 1.2 && Date().timeIntervalSince(lastVoice) >= 0.6
        if ended || duration >= 6 { flush() }
    }

    private func flush() {
        let url = writer?.url
        writer = nil
        let useful = hasSpeech
        hasSpeech = false
        opened = Date()
        guard let url else { return }
        guard useful, tasks.count < 2 else {
            try? FileManager.default.removeItem(at: url)
            if useful { onDraft("WhisperX занят. Для меньшей задержки выберите macOS.") }
            return
        }
        let number = sequence
        sequence += 1
        onDraft("Распознаю фразу…")
        tasks[number] = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            var text = ""
            do {
                let segments = try await WhisperX.transcribe(file: url, config: self.config, session: self.session)
                try Task.checkCancellation()
                text = segments.map(\.text).joined(separator: " ")
            } catch {
                if !Task.isCancelled {
                    if case WhisperX.Failure.noSpeech = error { }
                    else {
                        if case WhisperX.Failure.auth = error { await self.session.forget() }
                        self.onError("WhisperX: \(error.localizedDescription)")
                    }
                }
            }
            let finalText = text
            self.queue.async {
                self.tasks[number] = nil
                guard self.running else { return }
                self.ready[number] = finalText
                while let text = self.ready.removeValue(forKey: self.nextToShow) {
                    self.nextToShow += 1
                    if !text.isEmpty { self.onUtterance(text) }
                }
                if self.tasks.isEmpty { self.onDraft("") }
            }
        }
    }
}
