import Foundation

enum TechnicalVocabulary {
    struct Alternative: Equatable, Identifiable {
        let term: String
        let question: String
        var id: String { term }
    }

    private static let core = ["API", "IP", "IP-адрес", "REST API", "HTTP", "SQL", "Git"]
    private static let terms = [
        "Python", "Java", "JavaScript", "TypeScript", "C++", "C#", ".NET", "Go", "Rust", "Swift", "Kotlin",
        "HTML", "CSS", "React", "Vue", "Angular", "Node.js", "FastAPI", "Django", "Flask", "Spring",
        "PostgreSQL", "MySQL", "SQLite", "MongoDB", "Redis", "Elasticsearch", "Kafka", "RabbitMQ",
        "Docker", "Kubernetes", "Linux", "Nginx", "GitHub", "GitLab", "CI/CD", "Jenkins", "Terraform",
        "TCP", "UDP", "DNS", "HTTPS", "JSON", "XML", "gRPC", "GraphQL", "WebSocket", "OAuth", "JWT",
        "pytest", "unittest", "JUnit", "Selenium", "Playwright", "Postman", "Swagger", "OpenAPI",
        "QA", "DevOps", "backend", "frontend", "SOLID", "ООП", "ACID", "CAP", "GIL", "asyncio",
        "NumPy", "pandas", "PyTorch", "TensorFlow", "Prometheus", "Grafana"
    ]

    private static func word(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])(?:" + pattern + ")(?![\\p{L}\\p{N}_])",
                                 options: .caseInsensitive)
    }

    private static let aliases: [(NSRegularExpression, String)] = [
        ("эй[\\s-]+пи[\\s-]+ай|ай[\\s-]+пи[\\s-]+ай|эйпиай", "API"),
        ("фаст[\\s-]+апи|фастапи", "FastAPI"),
        ("рест[\\s-]+апи", "REST API"),
        ("си[\\s-]+плюс[\\s-]+плюс", "C++"),
        ("си[\\s-]+шарп", "C#"),
        ("джава[\\s-]*скрипт|джаваскрипт|жаваскрипт", "JavaScript"),
        ("тайп[\\s-]*скрипт|тайпскрипт", "TypeScript"),
        ("эс[\\s-]+кью[\\s-]+(?:эл|эль)|сиквел", "SQL"),
        ("ай[\\s-]+пи|айпи", "IP"),
        ("апи", "API"),
        ("питон(?:а|е|ом)?|пайтон(?:а|е|ом)?", "Python"),
        ("постгрес(?:а|е|ом)?|постгрескьюэль", "PostgreSQL"),
        ("джава", "Java"),
        ("докер(?:а|е|ом)?", "Docker"),
        ("кубернетес(?:а|е|ом)?", "Kubernetes"),
        ("редис(?:а|е|ом)?", "Redis"),
        ("джанго", "Django"),
        ("пайтест|пай[\\s-]+тест", "pytest")
    ].map { (word($0.0), $0.1) }
    private static let ip = word("IP")
    private static let api = word("API")
    private static let networkTerms = word("NAT|address(?:es)?|network(?:ing)?|subnets?|netmask|routers?|routing|packets?|hosts?")

    /// Только однозначные произношения. IP никогда не заменяется на API.
    static func normalize(_ text: String) -> String {
        aliases.reduce(text) { value, alias in
            alias.0.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value),
                                             withTemplate: alias.1)
        }
    }

    static func alternatives(for text: String) -> [Alternative] {
        let range = NSRange(text.startIndex..., in: text)
        guard ip.firstMatch(in: text, range: range) != nil,
              api.firstMatch(in: text, range: range) == nil else { return [] }
        let value = text.lowercased()
        let explicitMeaning = ["адрес", "ipv4", "ipv6", "tcp", "udp", "dns", "dhcp", "подсет", "сетев", "сети",
                               "сетях", "сеть", "маск", "маршрут", "пакет", "icmp", "хост", "интеллектуал",
                               "собственност", "патент", "лиценз", "авторск", "intellectual", "property"]
        guard !explicitMeaning.contains(where: value.contains), networkTerms.firstMatch(in: text, range: range) == nil else { return [] }
        return [("API", "API"), ("IP", "IP-адрес")].map { term, replacement in
            Alternative(term: term, question: ip.stringByReplacingMatches(in: text, range: range, withTemplate: replacement))
        }
    }

    /// В контекст распознавателя попадают названия технологий, а не всё резюме.
    /// Ограничение Apple — до 100 коротких фраз. Свои термины имеют приоритет.
    static func hints(custom: String, context: [String]) -> [String] {
        let supplied = String(custom.prefix(4_000)).components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 64 && !$0.contains("@") && !$0.contains("://") }
            .prefix(50)
        let profile = normalize(context.map { String($0.prefix(24_000)) }.joined(separator: " ")).lowercased()
        let relevant = terms.filter { profile.contains($0.lowercased()) }
        var seen = Set<String>()
        return Array((core + supplied + relevant + terms).filter { seen.insert($0.lowercased()).inserted }.prefix(100))
    }
}
