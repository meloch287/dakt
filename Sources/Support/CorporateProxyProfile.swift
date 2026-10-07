import Foundation

/// Читает только выбранный корпоративный provider и текущую авторизацию.
/// Никакие команды Codex не запускаются; OAuth-токен перечитывается перед
/// запросом, чтобы подхватить обновление входа, сделанное самим Codex.
struct CorporateProxyProfile {
    static var isAvailable: Bool {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.toml").path)
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent("auth.json").path)
    }

    static func load() throws -> LunaConfiguration {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let config = try String(contentsOf: root.appendingPathComponent("config.toml"), encoding: .utf8)
        let auth = try Data(contentsOf: root.appendingPathComponent("auth.json"))
        return try parse(config: config, auth: auth)
    }

    static func parse(config: String, auth: Data) throws -> LunaConfiguration {
        let top = config.components(separatedBy: "\n[").first ?? config
        guard let provider = string("model_provider", in: top) else {
            throw RecorderError.message("В Codex не выбран корпоративный провайдер. Введите ключи вручную.")
        }
        let sections = config.components(separatedBy: "\n[")
        let title = "model_providers.\(provider)]"
        guard let section = sections.first(where: { $0.hasPrefix(title) || $0.hasPrefix("[" + title) }),
              let base = string("base_url", in: section),
              let url = URL(string: base), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw RecorderError.message("У выбранного профиля Codex нет корректного HTTPS-адреса. Укажите адрес и ключи вручную.")
        }
        let headers = sections.first { $0.hasPrefix("model_providers.\(provider).http_headers]") } ?? ""
        let proxy = string("X-Proxy-Token", in: section + "\n" + headers) ?? ""
        guard let data = try JSONSerialization.jsonObject(with: auth) as? [String: Any] else {
            throw RecorderError.message("Не удалось прочитать вход Codex.")
        }
        let tokens = data["tokens"] as? [String: Any] ?? [:]
        let key = (data["OPENAI_API_KEY"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? tokens["access_token"] as? String ?? ""
        guard !key.isEmpty, !proxy.isEmpty else {
            throw RecorderError.message("Нужны вход Codex и токен корпоративного прокси. Обновите их или введите ключи вручную.")
        }
        let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/responses"
        return LunaConfiguration(endpoint: endpoint, apiKey: key, proxyToken: proxy,
                                 accountID: tokens["account_id"] as? String ?? "")
    }

    // Поддерживаем строковые поля и inline-таблицу http_headers. Не читаем
    // команды, MCP, хуки и прочие настройки агентского окружения.
    private static func string(_ key: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?:^|[\\s{,])\\\"?" + escaped + "\\\"?\\s*=\\s*(\"(?:\\\\.|[^\"\\\\])*\"|'[^']*')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let quoted = String(text[range])
        if quoted.first == "'" { return String(quoted.dropFirst().dropLast()) }
        return try? JSONDecoder().decode(String.self, from: Data(quoted.utf8))
    }
}
