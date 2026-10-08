import Foundation

/// Соединяет последовательные результаты до настоящего конца реплики.
struct SpeechTurnBuffer {
    private var parts: [String] = []
    var text: String { parts.joined(separator: " ") }
    var isEmpty: Bool { parts.isEmpty }

    mutating func append(_ text: String, endsTurn: Bool) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { parts.append(value) }
        guard endsTurn else { return nil }
        let result = self.text
        parts.removeAll(keepingCapacity: true)
        return result.isEmpty ? nil : result
    }

    func preview(appending text: String) -> String {
        [self.text, text].filter { !$0.isEmpty }.joined(separator: " ")
    }

    mutating func reset() { parts.removeAll(keepingCapacity: true) }
}
