import Foundation

@MainActor
final class AnswerEngine: ObservableObject {
    struct Reply: Identifiable, Equatable {
        let id: UUID
        let question: String
        var text: String
        var isStreaming: Bool
        var latency: TimeInterval?
    }
    private struct Job {
        let question: String
        let recent: [String]
        var config: LunaConfiguration
    }
    typealias Request = (String, [String], LunaConfiguration, @escaping @Sendable (String) -> Void) async throws -> String

    @Published private(set) var reply: Reply?
    @Published private(set) var history: [Reply] = []
    @Published private(set) var error: String?
    @Published private(set) var pendingCount = 0
    private let request: Request
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pending: [Job] = []
    private var currentJob: Job?

    init(request: @escaping Request = { question, recent, config, partial in
        try await LunaService.answer(question: question, recent: recent, config: config, onPartial: partial)
    }) { self.request = request }

    /// Автоматические вопросы обрабатываются последовательно. Прерывание
    /// допускается только по явному действию «Ответить сейчас».
    func ask(_ question: String, recent: [String], config: LunaConfiguration, interrupt: Bool = false) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        if interrupt {
            cancel()
            error = nil
        }
        pending.append(Job(question: question, recent: Array(recent.suffix(8)), config: config))
        pendingCount = pending.count
        startNext()
    }

    /// После ошибки повторяем тот же вопрос, сохраняя последующие в очереди.
    func retry(config: LunaConfiguration) {
        guard var job = currentJob else { return }
        cancelActive()
        job.config = config
        for index in pending.indices { pending[index].config = config }
        start(job, archivePrevious: false)
    }

    private func startNext() {
        guard task == nil, error == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        pendingCount = pending.count
        start(job)
    }

    private func start(_ job: Job, archivePrevious: Bool = true) {
        if archivePrevious, let previous = reply, !previous.text.isEmpty {
            history.insert(previous, at: 0)
            history = Array(history.prefix(20))
        }
        let id = UUID()
        generation = id
        currentJob = job
        reply = Reply(id: id, question: job.question, text: "", isStreaming: true)
        error = nil
        let started = Date()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.request(job.question, job.recent, job.config) { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.generation == id, self.reply?.isStreaming == true else { return }
                        self.reply?.text = partial
                        if self.reply?.latency == nil { self.reply?.latency = Date().timeIntervalSince(started) }
                    }
                }
                guard !Task.isCancelled, self.generation == id else { return }
                self.reply?.text = text
                self.reply?.isStreaming = false
                if self.reply?.latency == nil { self.reply?.latency = Date().timeIntervalSince(started) }
                self.task = nil
                self.startNext()
            } catch {
                guard !Task.isCancelled, self.generation == id else { return }
                self.reply?.isStreaming = false
                self.task = nil
                self.error = error.localizedDescription
                // Не скрываем ошибку следующим запросом: очередь ждёт повтора.
            }
        }
    }

    private func cancelActive() {
        generation = UUID()
        task?.cancel()
        task = nil
        reply?.isStreaming = false
    }

    func cancel() {
        cancelActive()
        pending = []
        pendingCount = 0
        currentJob = nil
        error = nil
    }

    func clear() {
        cancel()
        reply = nil
        history = []
        error = nil
    }

    func showExample(queued: Int = 0, waitingForNext: Bool = false) {
        cancel()
        error = nil
        pendingCount = queued
        reply = Reply(id: UUID(), question: "Как бы ты сократил время загрузки приложения?",
                      text: "Сначала измерю, на что уходит время: сеть, запуск или отрисовка. Затем уберу лишнее с критического пути — тяжёлые модули загружу по требованию, независимые запросы запущу параллельно.\n\nРезультат проверю по времени до первого полезного экрана и по 95-му перцентилю на реальных устройствах.", isStreaming: false, latency: 0.8)
        if waitingForNext, let completed = reply {
            history = [completed]
            reply = Reply(id: UUID(), question: "Какие метрики ты будешь отслеживать?", text: "", isStreaming: true)
        }
    }
}
