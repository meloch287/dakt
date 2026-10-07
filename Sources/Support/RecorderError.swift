import Foundation

/// Ошибка с готовым текстом для пользователя. Всё, что уходит в интерфейс,
/// формулируется по-русски и с подсказкой, что делать.
enum RecorderError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
