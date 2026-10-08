import Foundation

/// Отсеивает подтверждения и фоновую речь без дополнительного запроса к модели.
enum QuestionGate {
    static func shouldAnswer(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count >= 3 else { return false }
        if value.contains("?") { return true }
        // Встроенный диктующий движок может вернуть длинную реплику без
        // пунктуации. Явная просьба в её конце всё равно является вопросом.
        let allWords = value.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let requests: Set<String> = [
            "расскажи", "расскажите", "объясни", "объясните", "опиши", "опишите",
            "сравни", "сравните", "предложи", "предложите", "назови", "назовите",
            "приведи", "приведите", "посчитай", "реши", "explain", "describe", "compare", "tell", "calculate"
        ]
        if allWords.contains(where: requests.contains) { return true }
        let starters: Set<String> = [
            "как", "почему", "зачем", "что", "кто", "где", "когда", "какой", "какая", "какие", "какое",
            "сколько", "чем", "кому", "можно", "можешь", "можете", "расскажи", "расскажите",
            "объясни", "объясните", "опиши", "опишите", "сравни", "сравните", "предложи", "предложите",
            "допустим", "представь", "представьте", "назови", "назовите", "посчитай", "реши",
            "how", "why", "what", "who", "where", "when", "which", "can", "could", "would",
            "explain", "describe", "compare", "tell", "calculate"
        ]
        let addressed = allWords.indices.contains { index in
            starters.contains(allWords[index]) && allWords.dropFirst(index + 1).prefix(3).contains {
                ["вы", "ты", "you"].contains($0)
            }
        }
        return addressed || value.components(separatedBy: CharacterSet(charactersIn: ".!;\n")).contains { sentence in
            let words = sentence.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            return words.prefix(5).contains { starters.contains($0) } || words.prefix(7).contains("ли")
        }
    }
}

/// Speech присылает всю фразу заново при каждом уточнении. Уже показанная
/// часть не должна повторно запускать модель после паузы или финализации.
struct UtteranceBuffer {
    private(set) var committedWords = 0
    private(set) var current = ""

    mutating func update(_ cumulative: String) -> String {
        let words = cumulative.split(whereSeparator: \.isWhitespace)
        if words.count < committedWords { committedWords = 0 }
        current = words.dropFirst(committedWords).joined(separator: " ")
        return current
    }

    mutating func commit(_ cumulative: String) -> String? {
        let tail = update(cumulative).trimmingCharacters(in: .whitespacesAndNewlines)
        committedWords = cumulative.split(whereSeparator: \.isWhitespace).count
        current = ""
        return tail.isEmpty ? nil : tail
    }

    mutating func reset() { self = UtteranceBuffer() }
}
