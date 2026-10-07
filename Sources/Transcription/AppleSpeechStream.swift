import AVFoundation
import Speech

/// Один поток, одна сторона разговора. Вопрос фиксируется после 600 мс
/// тишины, не дожидаясь минутного лимита системного распознавателя.
final class AppleSpeechStream: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dakt.speech.apple", qos: .userInitiated)
    private let recognizer: SFSpeechRecognizer
    private let onDraft: (String) -> Void
    private let onUtterance: (String) -> Void
    private let onError: (SpeechFailure) -> Void
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: DispatchSourceTimer?
    private var running = false
    private var generation = 0
    private var errors = 0
    private var lastVoice = Date.distantPast
    private var lastTextAt = Date.distantPast
    private var taskStarted = Date()
    private var lastText = ""
    private var buffer = UtteranceBuffer()

    init(locale: String, onDraft: @escaping (String) -> Void,
         onUtterance: @escaping (String) -> Void, onError: @escaping (SpeechFailure) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw RecorderError.message("Распознавание macOS недоступно. Включите диктовку и проверьте выбранный язык в настройках.")
        }
        self.recognizer = recognizer
        self.onDraft = onDraft
        self.onUtterance = onUtterance
        self.onError = onError
    }

    static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start() {
        queue.async {
            self.running = true
            self.beginTask()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    func append(_ audio: AVAudioPCMBuffer) {
        queue.async {
            guard self.running else { return }
            if audio.peakLevel > 0.012 { self.lastVoice = Date() }
            self.request?.append(audio)
        }
    }

    func stop() {
        queue.sync {
            running = false
            generation += 1
            timer?.cancel()
            timer = nil
            request?.endAudio()
            task?.cancel()
            request = nil
            task = nil
            buffer.reset()
        }
    }

    private func beginTask() {
        guard running else { return }
        generation += 1
        let ticket = generation
        task?.cancel()
        request?.endAudio()
        buffer.reset()
        lastText = ""
        taskStarted = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard self.running, self.generation == ticket else { return }
                if let result {
                    self.errors = 0
                    self.lastText = result.bestTranscription.formattedString
                    self.lastTextAt = Date()
                    self.onDraft(self.buffer.update(self.lastText))
                    if result.isFinal {
                        self.commit()
                        self.beginTask()
                        return
                    }
                }
                if let error {
                    let failure = SpeechFailure(error)
                    self.commit()
                    self.errors += 1
                    self.generation += 1
                    self.task?.cancel()
                    self.request = nil
                    guard failure.isRetryable, self.errors <= 2 else {
                        self.running = false
                        self.onError(failure)
                        return
                    }
                    self.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.beginTask() }
                }
            }
        }
    }

    private func tick() {
        guard running else { return }
        let now = Date()
        // Короткий запас после уточнения текста даёт распознавателю дописать
        // последнее слово, но не добавляет прежнюю задержку в несколько секунд.
        if now.timeIntervalSince(lastVoice) >= 0.6 && now.timeIntervalSince(lastTextAt) >= 0.2 { commit() }
        if now.timeIntervalSince(taskStarted) >= 45 {
            commit()
            beginTask()
        }
    }

    private func commit() {
        guard let text = buffer.commit(lastText) else { return }
        onDraft("")
        onUtterance(text)
    }
}
