import Foundation
import AVFoundation
import Speech

/// Современный API разбирает готовый аудиофрагмент локально. В отличие от
/// SFSpeechRecognizer, не требует включать Siri или клавиатурную диктовку.
enum AudioClipTranscriber {
    static var isSupported: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    static func prepare(locale identifier: String) async throws {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
                throw RecorderError.message("Этот язык недоступен для быстрых аудиофрагментов. Выберите другой язык или режим «Диктовка macOS».")
            }
            let installed = await DictationTranscriber.installedLocales
            guard installed.contains(where: { normalized($0.identifier) == normalized(locale.identifier) }) else {
                throw RecorderError.message("Локальная модель языка \(identifier) ещё не установлена. Установите этот язык в настройках диктовки macOS.")
            }
            // Резервирование относится к приложению и повторно использует язык
            // между фрагментами; установленную модель не скачиваем заново.
            // false означает «уже зарезервирован», а не ошибку.
            _ = try await AssetInventory.reserve(locale: locale)
            let module = DictationTranscriber(locale: locale, preset: .shortDictation)
            let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
            do {
                try await analyzer.prepareToAnalyze(in: nil)
                await analyzer.cancelAndFinishNow()
                try Task.checkCancellation()
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
            return
        }
        #endif
        throw RecorderError.message("Быстрые аудиофрагменты требуют macOS 26. На этой системе выберите режим «Диктовка macOS».")
    }

    static func recognize(file: URL, locale identifier: String) async throws -> String {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
                throw RecorderError.message("Этот язык недоступен для быстрых аудиофрагментов.")
            }
            let module = DictationTranscriber(locale: locale, preset: .shortDictation)
            let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
            let reading = Task { () throws -> String in
                var parts: [String] = []
                for try await result in module.results {
                    try Task.checkCancellation()
                    parts.append(String(result.text.characters))
                }
                return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            defer { reading.cancel() }
            return try await withTaskCancellationHandler {
                do {
                    let audio = try AVAudioFile(forReading: file)
                    let end = try await analyzer.analyzeSequence(from: audio)
                    try Task.checkCancellation()
                    if let end { try await analyzer.finalizeAndFinish(through: end) }
                    else { await analyzer.cancelAndFinishNow() }
                    return try await reading.value
                } catch {
                    await analyzer.cancelAndFinishNow()
                    throw error
                }
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
        #endif
        throw RecorderError.message("Быстрые аудиофрагменты требуют macOS 26.")
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
