import Foundation

@MainActor
final class AssistantPreferences: ObservableObject {
    enum SpeechEngine: String, CaseIterable, Identifiable {
        case clips, apple
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clips: return "Аудиофрагменты · быстро"
            case .apple: return "Диктовка macOS · старый режим"
            }
        }
        static var available: [SpeechEngine] {
            allCases.filter { $0 != .clips || AudioClipTranscriber.isSupported }
        }

        static func restore(_ rawValue: String?, supportsClips: Bool) -> SpeechEngine {
            guard let saved = SpeechEngine(rawValue: rawValue ?? "") else {
                return supportsClips ? .clips : .apple
            }
            return saved == .clips && !supportsClips ? .apple : saved
        }
    }

    private let defaults: UserDefaults
    private let preview: Bool
    @Published var useCodexLogin: Bool { didSet { save(useCodexLogin, "useCodexLogin") } }
    @Published var endpoint: String { didSet { save(endpoint, "endpoint") } }
    @Published var apiKey: String { didSet { if !preview { Secrets.write(apiKey, "lunaKey") } } }
    @Published var proxyToken: String { didSet { if !preview { Secrets.write(proxyToken, "lunaProxy") } } }
    @Published var context: String { didSet { save(context, "context") } }
    @Published var resumeText: String { didSet { save(resumeText, "resumeText") } }
    @Published var resumeName: String { didSet { save(resumeName, "resumeName") } }
    @Published var meetingDetails: String { didSet { save(meetingDetails, "meetingDetails") } }
    @Published var engine: SpeechEngine { didSet { save(engine.rawValue, "engine") } }
    @Published var locale: String { didSet { save(locale, "locale") } }
    @Published var opacity: Double { didSet { save(opacity, "opacity") } }
    @Published var fontSize: Double { didSet { save(fontSize, "fontSize") } }
    @Published var stayOnTop: Bool { didSet { save(stayOnTop, "stayOnTop") } }
    @Published var privateMode: Bool { didSet { save(privateMode, "privateMode") } }
    @Published var showTranscript: Bool { didSet { save(showTranscript, "showTranscript") } }
    /// На новом запуске управление всегда доступно; положение окна сохраняется отдельно.
    @Published var windowLocked = false
    @Published var hotKey: KeyCombo {
        didSet { save(Int(hotKey.keyCode), "hotKeyCode"); save(Int(hotKey.modifiers), "hotKeyModifiers") }
    }

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults
        self.preview = preview
        func value(_ key: String) -> Any? { preview ? nil : defaults.object(forKey: "assistant." + key) }
        useCodexLogin = value("useCodexLogin") as? Bool ?? (!preview && CorporateProxyProfile.isAvailable)
        endpoint = value("endpoint") as? String ?? LunaConfiguration.defaultEndpoint
        apiKey = preview ? "" : Secrets.read("lunaKey")
        proxyToken = preview ? "" : Secrets.read("lunaProxy")
        context = value("context") as? String ?? ""
        resumeText = value("resumeText") as? String ?? ""
        resumeName = value("resumeName") as? String ?? ""
        meetingDetails = value("meetingDetails") as? String ?? ""
        // Один раз переводим прежний сценарий на обработку коротких записей.
        // Последующий явный выбор другого движка сохраняется.
        let enableClips = AudioClipTranscriber.isSupported
            && (preview || defaults.object(forKey: "assistant.clipModeInitialized") as? Bool != true)
        engine = SpeechEngine.restore(enableClips ? SpeechEngine.clips.rawValue : value("engine") as? String,
                                      supportsClips: AudioClipTranscriber.isSupported)
        locale = value("locale") as? String ?? "ru-RU"
        opacity = min(1, max(0.35, value("opacity") as? Double ?? 0.84))
        fontSize = min(32, max(13, value("fontSize") as? Double ?? 19))
        stayOnTop = value("stayOnTop") as? Bool ?? true
        privateMode = value("privateMode") as? Bool ?? true
        showTranscript = value("showTranscript") as? Bool ?? true
        if let code = value("hotKeyCode") as? Int, let modifiers = value("hotKeyModifiers") as? Int,
           code >= 0, code <= Int(UInt32.max), modifiers >= 0, modifiers <= Int(UInt32.max) {
            hotKey = KeyCombo(keyCode: UInt32(code), modifiers: UInt32(modifiers))
        } else { hotKey = .default }
        if !preview {
            if enableClips { defaults.set(true, forKey: "assistant.clipModeInitialized") }
            // Неизвестный или недоступный режим заменяем встроенным и
            // сохраняем исправленный выбор для следующего запуска.
            if defaults.string(forKey: "assistant.engine") != engine.rawValue {
                defaults.set(engine.rawValue, forKey: "assistant.engine")
            }
        }
    }

    func lunaConfiguration() throws -> LunaConfiguration {
        var config = useCodexLogin ? try CorporateProxyProfile.load()
            : LunaConfiguration(endpoint: endpoint, apiKey: apiKey, proxyToken: proxyToken)
        config.context = context
        config.resume = resumeText
        guard config.isReady else { throw RecorderError.message("Подключите корпоративный прокси в настройках.") }
        return config
    }

    private func save(_ value: Any, _ key: String) {
        guard !preview else { return }
        defaults.set(value, forKey: "assistant." + key)
    }
}
