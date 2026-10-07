import SwiftUI

struct AssistantSettingsView: View {
    @ObservedObject var preferences: AssistantPreferences
    @ObservedObject var assistant: AssistantController
    @State private var testStatus: String?
    @State private var testing = false
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Подстроить под разговор").font(.system(size: 22, weight: .semibold))
                    Text("GPT‑6 Luna · без рассуждений · ответы потоком")
                        .font(.caption).foregroundStyle(AssistantTheme.secondary)
                }
                MeetingContextEditor(preferences: preferences, editor: assistant.meetingContext)
                section("Подключение") {
                    Toggle("Использовать корпоративный профиль Codex", isOn: $preferences.useCodexLogin)
                    if preferences.useCodexLogin {
                        detail("Адрес и токен прокси берутся из настроек Codex, авторизация — из его текущего входа. Запросы идут напрямую через корпоративный прокси, без запуска агента.")
                    } else {
                        TextField("HTTPS-адрес /responses", text: $preferences.endpoint)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Ключ доступа", text: $preferences.apiKey)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Токен прокси · X-Proxy-Token", text: $preferences.proxyToken)
                            .textFieldStyle(.roundedBorder)
                        detail("Ключи хранятся в Связке ключей macOS.")
                    }
                    HStack(spacing: 10) {
                        Button(testing ? "Проверяю…" : "Проверить подключение", action: testConnection)
                            .disabled(testing)
                        if testing { ProgressView().controlSize(.small) }
                    }
                    if let testStatus { detail(testStatus) }
                }
                section("Распознавание собеседника") {
                    Picker("Движок", selection: $preferences.engine) {
                        ForEach(AssistantPreferences.SpeechEngine.available) { engine in Text(engine.title).tag(engine) }
                    }
                    Picker("Язык", selection: $preferences.locale) {
                        Text("Русский").tag("ru-RU")
                        Text("English").tag("en-US")
                        Text("Deutsch").tag("de-DE")
                        Text("Español").tag("es-ES")
                        Text("Français").tag("fr-FR")
                    }
                    if preferences.engine == .clips {
                        detail("Записывает короткую фразу и сразу переводит её в текст на компьютере. Пауза — 0,4 с. Siri и системную диктовку включать не нужно. Временная запись удаляется после обработки. Требуется macOS 26 и установленная модель языка.")
                    } else {
                        detail("Старый потоковый режим. Нужна включённая диктовка macOS. Если язык не поддерживает распознавание на устройстве, звук обрабатывается Apple.")
                    }
                    if assistant.state != .idle {
                        detail("Чтобы изменить распознавание, поставьте прослушивание на паузу.")
                    }
                }
                .disabled(assistant.state != .idle)
                section("Окно") {
                    HStack {
                        Text("Плотность фона")
                        Spacer()
                        Text("\(Int(preferences.opacity * 100)) %").monospacedDigit().foregroundStyle(AssistantTheme.secondary)
                    }
                    Slider(value: $preferences.opacity, in: 0.35...1, step: 0.01)
                        .accessibilityLabel("Плотность фона")
                    HStack {
                        Text("Размер ответа")
                        Spacer()
                        Text("\(Int(preferences.fontSize)) pt").monospacedDigit().foregroundStyle(AssistantTheme.secondary)
                    }
                    Slider(value: $preferences.fontSize, in: 13...32, step: 1)
                        .accessibilityLabel("Размер шрифта ответа")
                    Toggle("Поверх других окон", isOn: $preferences.stayOnTop)
                    Toggle("Показывать текущую речь", isOn: $preferences.showTranscript)
                    detail("Тяните за любой край или угол окна. Размер и положение запоминаются.")
                }
                section("Демонстрация экрана") {
                    Toggle("Приватный режим", isOn: $preferences.privateMode)
                    detail("Убирает Dakt из Dock и включает исключение из захвата там, где оно поддерживается.")
                    Label {
                        Text("На новых macOS окно может попадать в захват всего экрана. Чтобы собеседники точно не видели подсказки, демонстрируйте отдельное окно приложения.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "rectangle.on.rectangle.slash") }
                    .font(.caption)
                    .foregroundStyle(Color(red: 1, green: 0.79, blue: 0.59))
                    HStack {
                        Text("Скрыть / показать")
                        Spacer()
                        ShortcutRecorder(combo: $preferences.hotKey)
                    }
                    detail("Скрытие окна не останавливает прослушивание. Пауза доступна через значок Dakt у часов. ⌘L — пауза в активном окне.")
                }
                section("Источник звука") {
                    Label("Весь системный звук экрана", systemImage: "display")
                    detail("VK Teams, Zoom, браузер и всё остальное, что звучит на компьютере. Микрофон не используется. Короткие аудиофрагменты удаляются после обработки; постоянной записи встречи нет.")
                }
            }
            .padding(26)
        }
        .frame(minWidth: 360, minHeight: 400)
        .background(AssistantTheme.surface)
        .preferredColorScheme(.dark)
        .tint(AssistantTheme.accent)
        .onDisappear { connectionTask?.cancel() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content().font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(AssistantTheme.secondary)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func testConnection() {
        testing = true
        testStatus = nil
        connectionTask = Task {
            defer { testing = false }
            do {
                var config = try preferences.lunaConfiguration()
                config.context = ""
                config.resume = ""
                let started = Date()
                _ = try await LunaService.answer(question: "Ответь одним словом: готово.", recent: [], config: config, onPartial: { _ in })
                guard !Task.isCancelled else { return }
                testStatus = String(format: "Luna отвечает. Проверка заняла %.1f с.", Date().timeIntervalSince(started))
            } catch {
                if !Task.isCancelled { testStatus = error.localizedDescription }
            }
        }
    }
}
