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
    typealias Request = (String, [String], LunaConfiguration, @escaping @Sendable (String) -> Void) async throws -> String

    @Published private(set) var reply: Reply?
    @Published private(set) var history: [Reply] = []
    @Published private(set) var error: String?
    private let request: Request
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(request: @escaping Request = { question, recent, config, partial in
        try await LunaService.answer(question: question, recent: recent, config: config, onPartial: partial)
    }) { self.request = request }

    func ask(_ question: String, recent: [String], config: LunaConfiguration) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        cancel()
        if let previous = reply, !previous.text.isEmpty {
            history.insert(previous, at: 0)
            history = Array(history.prefix(20))
        }
        let id = UUID()
        generation = id
        reply = Reply(id: id, question: question, text: "", isStreaming: true)
        error = nil
        let started = Date()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.request(question, recent, config) { [weak self] partial in
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
            } catch {
                guard !Task.isCancelled, self.generation == id else { return }
                self.reply?.isStreaming = false
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        reply?.isStreaming = false
    }

    func clear() {
        cancel()
        reply = nil
        history = []
        error = nil
    }

    func showExample() {
        reply = Reply(id: UUID(), question: "Как бы ты сократил время загрузки приложения?",
                      text: "Сначала измерю, на что уходит время: сеть, запуск или отрисовка. Затем уберу лишнее с критического пути — тяжёлые модули загружу по требованию, независимые запросы запущу параллельно.\n\nРезультат проверю по времени до первого полезного экрана и по 95-му перцентилю на реальных устройствах.", isStreaming: false, latency: 0.8)
    }
}
