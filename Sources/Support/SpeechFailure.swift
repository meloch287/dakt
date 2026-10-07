import Foundation

enum SystemRecovery: Equatable {
    case dictation, speechRecognition, screenRecording

    var title: String {
        switch self {
        case .dictation: return "Открыть диктовку"
        case .speechRecognition: return "Доступ к распознаванию"
        case .screenRecording: return "Доступ к экрану"
        }
    }

    var url: URL {
        let path: String
        switch self {
        case .dictation: path = "com.apple.Keyboard-Settings.extension?Dictation"
        case .speechRecognition: path = "com.apple.preference.security?Privacy_SpeechRecognition"
        case .screenRecording: path = "com.apple.preference.security?Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:" + path)!
    }
}

struct SpeechFailure: LocalizedError {
    let source: NSError
    init(_ error: Error) { source = error as NSError }

    private var dictationDisabled: Bool {
        var error: NSError? = source
        // Speech иногда оборачивает ошибку сервиса в kAFAssistantErrorDomain.
        for _ in 0..<8 {
            guard let current = error else { break }
            if current.domain == "kLSRErrorDomain", current.code == 201 { return true }
            if current.localizedDescription.localizedCaseInsensitiveContains("Siri and Dictation are disabled") { return true }
            error = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    var recovery: SystemRecovery? { dictationDisabled ? .dictation : nil }
    var isRetryable: Bool { !dictationDisabled }
    var errorDescription: String? {
        if dictationDisabled {
            return "В macOS выключена диктовка. Включите её: Системные настройки → Клавиатура → Диктовка. Выданное приложению разрешение само по себе её не включает. На macOS 26 можно выбрать режим «Аудиофрагменты · быстро»."
        }
        return "Распознавание прервалось. \(source.localizedDescription) (\(source.domain), \(source.code)). Повторите запуск и проверьте выбранный язык."
    }
}
