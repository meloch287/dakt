import Foundation

/// Один ожидающий снимок текста вместо MainActor-задачи на каждый токен.
/// Первый фрагмент доставляется сразу, остальные — не чаще 20 раз в секунду.
/// Последний снимок доходит и при паузе в сети; finish сохраняет его при ошибке.
final class StreamingTextDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: String?
    private var scheduled = false
    private var closed = false
    private let receive: @MainActor @Sendable (String) -> Void

    init(receive: @escaping @MainActor @Sendable (String) -> Void) { self.receive = receive }

    func submit(_ text: String) {
        let needsDelivery = lock.withLock { () -> Bool in
            guard !closed else { return false }
            pending = text
            guard !scheduled else { return false }
            scheduled = true
            return true
        }
        if needsDelivery {
            DispatchQueue.main.async { [weak self] in self?.deliver() }
        }
    }

    @MainActor private func deliver() {
        let text = lock.withLock { () -> String? in
            guard !closed else { return nil }
            guard let text = pending else { scheduled = false; return nil }
            pending = nil
            return text
        }
        guard let text else { return }
        receive(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.deliver() }
    }

    @MainActor func finish() {
        if let text = close() { receive(text) }
    }

    func cancel() { _ = close() }

    private func close() -> String? {
        lock.withLock {
            closed = true
            defer { pending = nil }
            return pending
        }
    }
}
