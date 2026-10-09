import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
final class AudioActivity: ObservableObject {
    @Published private var displayedLevel: Float = 0
    private var latestLevel: Float = 0
    private var visible = true

    var level: Float {
        get { displayedLevel }
        set {
            // Шаг меньше половины точки высоты индикатора. Незаметные
            // колебания и повторная тишина не требуют обновления SwiftUI.
            latestLevel = (min(1, max(0, newValue)) * 100).rounded() / 100
            publishIfNeeded()
        }
    }

    func setVisible(_ value: Bool) {
        visible = value
        publishIfNeeded()
    }

    private func publishIfNeeded() {
        if visible, displayedLevel != latestLevel { displayedLevel = latestLevel }
    }
}

@MainActor
final class AssistantController: ObservableObject {
    enum State: Equatable {
        case idle, starting, listening, stopping
        var title: String {
            switch self {
            case .idle: return "На паузе"
            case .starting: return "Подключаю звук"
            case .listening: return "Слушаю собеседника"
            case .stopping: return "Останавливаю"
            }
        }
    }
    struct Utterance: Identifiable {
        let id = UUID()
        let text: String
        let at = Date()
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: [Utterance] = []
    @Published private(set) var draft = ""
    @Published private(set) var captureStatus = ""
    @Published var error: String? { didSet { recovery = nil } }
    @Published private(set) var recovery: SystemRecovery?
    let preferences: AssistantPreferences
    let meetingContext: MeetingContextController
    let answers = AnswerEngine()
    let activity = AudioActivity()
    private let relay = AudioBufferRelay()
    private var listener: SystemAudioListener?
    private var apple: AppleSpeechStream?
    private var recorded: RecordedSpeechStream?
    private var generation = UUID()
    private var starting: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private let preview: Bool

    init(preferences: AssistantPreferences, preview: Bool = false) {
        self.preferences = preferences
        meetingContext = MeetingContextController(preferences: preferences)
        self.preview = preview
        if preview { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stop() }
        }
    }

    func toggle() {
        if state == .idle {
            starting = Task { await start() }
        } else if state != .stopping {
            Task { await stop() }
        }
    }

    func start() async {
        guard state == .idle, !preview else { return }
        let ticket = UUID()
        generation = ticket
        state = .starting
        error = nil
        do {
            _ = try preferences.lunaConfiguration()
            if preferences.engine == .apple {
                guard await AppleSpeechStream.authorize() else {
                    error = "Разрешите распознавание речи в настройках macOS."
                    recovery = .speechRecognition
                    await stop()
                    return
                }
            }
            guard generation == ticket, !Task.isCancelled else { return }
            let draft: (String) -> Void = { [weak self] text in
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    self.receiveDraft(text)
                }
            }
            let final: (String) -> Void = { [weak self] text in
                Task { @MainActor in
                    guard let self, self.generation == ticket, self.state == .listening else { return }
                    self.receive(text)
                }
            }
            let failure: (String) -> Void = { [weak self] text in
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    self.error = text
                    await self.stop()
                }
            }
            let vocabulary = preferences.recognitionVocabulary
            switch preferences.engine {
            case .clips:
                let stream = RecordedSpeechStream(locale: preferences.locale, pause: preferences.questionPause,
                                                  contextualStrings: vocabulary,
                                                  onDraft: draft, onUtterance: final, onError: failure)
                recorded = stream
                try await stream.start()
                guard generation == ticket, !Task.isCancelled else { stream.stop(); return }
                relay.route { stream.append($0) }
            case .apple:
                let stream = try AppleSpeechStream(locale: preferences.locale, pause: preferences.questionPause,
                                                   contextualStrings: vocabulary,
                                                   onDraft: draft, onUtterance: final) { [weak self] issue in
                    Task { @MainActor in
                        guard let self, self.generation == ticket else { return }
                        self.reportSpeechFailure(issue)
                        await self.stop()
                    }
                }
                apple = stream
                stream.start()
                relay.route { stream.append($0) }
            }
            let relay = self.relay
            let source = SystemAudioListener(onBuffer: { relay.feed($0) }, onLevel: { [weak self] level in
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    self.activity.level = level
                }
            }, onError: failure)
            listener = source
            try await source.start()
            guard generation == ticket, !Task.isCancelled else { await source.stop(); return }
            state = .listening
        } catch {
            guard generation == ticket else { return }
            if !Task.isCancelled {
                let systemError = error as NSError
                if systemError.domain == SCStreamErrorDomain,
                   systemError.code == SCStreamError.Code.userDeclined.rawValue {
                    self.error = "Разрешите запись экрана и системного звука в настройках macOS, затем перезапустите Dakt."
                    recovery = .screenRecording
                } else { self.error = error.localizedDescription }
            }
            await stop()
        }
    }

    func stop() async {
        guard state != .stopping else { return }
        generation = UUID()
        starting?.cancel()
        starting = nil
        state = .stopping
        relay.route(to: nil)
        apple?.stop()
        recorded?.stop()
        apple = nil
        recorded = nil
        answers.cancel()
        draft = ""
        captureStatus = ""
        activity.level = 0
        let source = listener
        listener = nil
        await source?.stop()
        state = .idle
    }

    func receive(_ text: String) {
        let text = (preferences.itVocabulary ? TechnicalVocabulary.normalize(text) : text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let recent = transcript.map(\.text)
        transcript.append(Utterance(text: text))
        transcript = Array(transcript.suffix(80))
        draft = ""
        captureStatus = ""
        if QuestionGate.shouldAnswer(text) { ask(text, recent: recent) }
    }

    func receiveDraft(_ text: String) {
        if preferences.engine == .apple { draft = preferences.itVocabulary ? TechnicalVocabulary.normalize(text) : text }
        else { captureStatus = text }
    }

    var canAnswerLatest: Bool { !draft.isEmpty || !transcript.isEmpty }

    var recognitionAlternatives: [TechnicalVocabulary.Alternative] {
        guard preferences.itVocabulary, draft.isEmpty, let text = transcript.last?.text else { return [] }
        return TechnicalVocabulary.alternatives(for: text)
    }

    func answerAlternative(_ alternative: TechnicalVocabulary.Alternative) {
        guard recognitionAlternatives.contains(alternative), !transcript.isEmpty else { return }
        transcript[transcript.count - 1] = Utterance(text: alternative.question)
        captureStatus = ""
        ask(alternative.question, recent: transcript.dropLast().map(\.text), interrupt: true)
    }

    func answerLatest() {
        guard let text = draft.isEmpty ? transcript.last?.text : draft else { return }
        let recent = draft.isEmpty ? Array(transcript.dropLast()) : transcript
        ask(text, recent: recent.map(\.text), interrupt: true)
    }

    func retry() {
        guard !preview else { return }
        do {
            let config = try preferences.lunaConfiguration()
            error = nil
            answers.retry(config: config)
        } catch { self.error = error.localizedDescription }
    }

    private func ask(_ text: String, recent: [String], interrupt: Bool = false) {
        guard !preview else { return }
        do {
            let config = try preferences.lunaConfiguration()
            error = nil
            answers.ask(text, recent: recent, config: config, interrupt: interrupt)
        } catch { self.error = error.localizedDescription }
    }

    func clear() {
        answers.clear()
        transcript = []
        draft = ""
        captureStatus = ""
        error = nil
    }

    func openScreenPermission() {
        NSWorkspace.shared.open(SystemRecovery.screenRecording.url)
    }

    func openRecoverySettings() {
        guard let recovery else { return }
        NSWorkspace.shared.open(recovery.url)
    }

    func reportSpeechFailure(_ failure: SpeechFailure) {
        error = failure.localizedDescription
        recovery = failure.recovery
    }

    func loadExample() {
        guard preview else { return }
        state = .listening
        transcript = [Utterance(text: "Давай обсудим производительность."),
                      Utterance(text: "Как бы ты сократил время загрузки приложения?")]
        activity.level = 0.35
        answers.showExample()
    }
}
