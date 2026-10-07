import Foundation
import PDFKit

enum ResumeImporter {
    static let maxCharacters = 24_000
    static let maxFileBytes = 10 * 1_024 * 1_024

    struct Document: Sendable {
        let text: String
        let name: String
    }

    static func validate(_ text: String) throws -> String {
        let text = text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RecorderError.message("Добавьте текст резюме.") }
        guard text.count <= maxCharacters else {
            throw RecorderError.message("Резюме длиннее 24 000 знаков. Сократите текст до основного опыта и проектов.")
        }
        return text
    }

    static func read(_ url: URL, displayName: String? = nil) throws -> Document {
        guard url.isFileURL else { throw RecorderError.message("Выберите файл резюме на компьютере.") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxFileBytes else { throw RecorderError.message("Резюме должно быть меньше 10 МБ.") }
        let text: String
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw RecorderError.message("Не удалось открыть PDF.") }
            guard !document.isLocked else { throw RecorderError.message("PDF защищён паролем. Выберите копию без пароля или вставьте текст.") }
            guard document.pageCount <= 50 else { throw RecorderError.message("В резюме больше 50 страниц. Выберите короткую версию.") }
            text = document.string ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RecorderError.message("В PDF нет текстового слоя. Вставьте текст резюме или выберите текстовый PDF.")
            }
        case "txt", "md":
            let data = try Data(contentsOf: url)
            guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw RecorderError.message("Не удалось прочитать текст. Сохраните файл в UTF‑8.")
            }
            text = decoded
        default:
            throw RecorderError.message("Поддерживаются PDF, TXT и Markdown. Можно также вставить текст резюме.")
        }
        return Document(text: try validate(text), name: displayName ?? url.lastPathComponent)
    }
}
