import Foundation

@MainActor
final class MeetingContextController: ObservableObject {
    typealias Request = (String, LunaConfiguration, @escaping @Sendable (String) -> Void) async throws -> String
    @Published private(set) var isImporting = false
    @Published private(set) var isGenerating = false
    @Published private(set) var draft = ""
    @Published private(set) var requiresApply = false
    @Published private(set) var status: String?
    @Published private(set) var error: String?
    @Published private(set) var previousContext: String?
    private let preferences: AssistantPreferences
    private let request: Request
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(preferences: AssistantPreferences, request: @escaping Request = { details, config, partial in
        try await LunaService.answer(question: details, recent: [], config: config,
                                     purpose: .meetingTemplate, onPartial: partial)
    }) {
        self.preferences = preferences
        self.request = request
    }

    var isBusy: Bool { isImporting || isGenerating }
    var canGenerate: Bool {
        !isBusy && !preferences.resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preferences.resumeText.count <= ResumeImporter.maxCharacters
    }

    func importResume(from url: URL, displayName: String? = nil) async {
        cancel()
        let token = generation
        isImporting = true
        error = nil
        status = nil
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try ResumeImporter.read(url, displayName: displayName)
            }.value
            guard generation == token else { return }
            preferences.resumeText = document.text
            preferences.resumeName = document.name
            isImporting = false
            generate()
        } catch {
            guard generation == token else { return }
            isImporting = false
            self.error = error.localizedDescription
        }
    }

    func importText(_ text: String) {
        do {
            let validated = try ResumeImporter.validate(text)
            cancel()
            preferences.resumeText = validated
            preferences.resumeName = "Текст из буфера"
            generate()
        } catch { self.error = error.localizedDescription }
    }

    func generate() {
        cancel()
        error = nil
        status = nil
        draft = ""
        requiresApply = false
        let resume: String
        let config: LunaConfiguration
        do {
            resume = try ResumeImporter.validate(preferences.resumeText)
            var value = try preferences.lunaConfiguration()
            value.resume = resume
            config = value
        } catch {
            self.error = error.localizedDescription
            return
        }
        let token = generation
        let originalResume = preferences.resumeText
        let details = preferences.meetingDetails
        let originalContext = preferences.context
        isGenerating = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.request(details, config) { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.isGenerating else { return }
                        self.draft = partial
                    }
                }
                guard !Task.isCancelled, self.generation == token else { return }
                self.isGenerating = false
                guard self.preferences.resumeText == originalResume, self.preferences.meetingDetails == details else {
                    self.draft = ""
                    self.status = "Резюме или сведения о встрече изменились. Сформируйте шаблон ещё раз."
                    return
                }
                let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty, result.count <= 12_000 else {
                    throw RecorderError.message("Не получился подходящий шаблон. Уточните цель встречи и повторите.")
                }
                self.draft = result
                if self.preferences.context == originalContext {
                    self.applyDraft()
                } else {
                    self.requiresApply = true
                    self.status = "Вы изменили контекст во время подготовки. Новый шаблон показан отдельно — ваши правки сохранены."
                }
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.isGenerating = false
                self.error = "Шаблон не подготовлен: \(error.localizedDescription)"
            }
        }
    }

    func applyDraft() {
        guard !draft.isEmpty, !isBusy else { return }
        previousContext = preferences.context
        preferences.context = draft
        requiresApply = false
        status = "Шаблон готов и используется в ответах. Его можно отредактировать ниже."
    }

    func restorePrevious() {
        guard let previousContext else { return }
        cancel()
        preferences.context = previousContext
        self.previousContext = nil
        requiresApply = false
        status = "Предыдущий контекст восстановлен."
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        if isBusy { status = "Подготовка остановлена." }
        isImporting = false
        isGenerating = false
    }
}
