import AppKit

@main
struct DaktRecorderApp {
    @MainActor
    static func main() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--benchmark-audio"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            Task.detached {
                do { try await AudioPipelineBenchmark.run(file: URL(fileURLWithPath: path)); exit(0) }
                catch { print("Audio benchmark: \(error.localizedDescription)"); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--check-proxy") {
            Task.detached {
                do {
                    let config = try CorporateProxyProfile.load()
                    let start = Date()
                    _ = try await LunaService.answer(question: "Ответь одним словом: готово.", recent: [], config: config) { _ in }
                    print(String(format: "GPT-6 Luna: ответ через корпоративный прокси, reasoning=none, %.2f с", Date().timeIntervalSince(start)))
                    exit(0)
                } catch {
                    print("Проверка прокси: \(error.localizedDescription)")
                    exit(1)
                }
            }
            dispatchMain()
        }
        #endif
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) { }
    }
}
