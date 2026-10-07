import SwiftUI
import AppKit

enum AssistantTheme {
    static let accent = Color(red: 0.57, green: 0.92, blue: 0.77)
    static let secondary = Color(red: 0.69, green: 0.73, blue: 0.75)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.10)
    static let line = Color.white.opacity(0.10)
}

struct AssistantView: View {
    @ObservedObject var assistant: AssistantController
    @ObservedObject var answers: AnswerEngine
    @ObservedObject var preferences: AssistantPreferences
    let onSettings: () -> Void
    let onHide: () -> Void
    let onLockControlChange: (NSView) -> Void
    var isPreview = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var copied = false
    @State private var previous: AnswerEngine.Reply?

    private var displayed: AnswerEngine.Reply? { previous ?? answers.reply }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header(compact: geometry.size.width < 410)
                Rectangle().fill(AssistantTheme.line).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = assistant.error ?? answers.error { errorBanner(error) }
                        if let reply = displayed { answer(reply, compact: geometry.size.height < 350) }
                        else { emptyState }
                    }
                    .padding(geometry.size.height < 350 ? 12 : (geometry.size.width < 360 ? 16 : 24))
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if preferences.showTranscript && geometry.size.height >= 310 {
                    speechStrip
                }
                footer(compact: geometry.size.width < 400)
            }
            .background {
                ZStack {
                    if !reduceTransparency { FrostedBackground().opacity(0.45) }
                    AssistantTheme.surface.opacity(reduceTransparency ? 1 : preferences.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .ignoresSafeArea()
        .frame(minWidth: 280, minHeight: 180)
        .preferredColorScheme(.dark)
        .tint(AssistantTheme.accent)
        .onChange(of: answers.reply?.id) { _ in previous = nil; copied = false }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 9) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundStyle(AssistantTheme.accent)
                Text("dakt").font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if isPreview && !compact {
                Text("ПРИМЕР").font(.system(size: 9, weight: .medium)).foregroundStyle(AssistantTheme.secondary)
            }
            if !compact {
                Text(assistant.state.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AssistantTheme.secondary)
                    .lineLimit(1)
            }
            Button(action: assistant.toggle) {
                HStack(spacing: 5) {
                    Image(systemName: assistant.state == .idle ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                    if !compact { Text(assistant.state == .idle ? "Слушать" : "Пауза").font(.system(size: 11, weight: .semibold)) }
                }
                .frame(minWidth: 18, minHeight: 28)
                .padding(.horizontal, 9)
                .background(AssistantTheme.accent.opacity(assistant.state == .listening ? 0.16 : 0.95), in: Capsule())
                .foregroundStyle(assistant.state == .listening ? AssistantTheme.accent : AssistantTheme.surface)
            }
            .buttonStyle(.plain)
            .disabled(assistant.state == .stopping || isPreview || preferences.windowLocked)
            .help(assistant.state == .idle ? "Начать слушать системный звук · ⌘L" : "Остановить прослушивание · ⌘L")
            .accessibilityLabel(assistant.state == .idle ? "Начать слушать" : "Остановить прослушивание")
            .keyboardShortcut("l", modifiers: .command)
            WindowLockButton(locked: preferences.windowLocked) { preferences.windowLocked.toggle() }
                // При блокировке тот же замок рисуется дочерним окном поверх
                // этого места. Остальная поверхность пропускает весь ввод.
                .opacity(preferences.windowLocked ? 0 : 1)
                .accessibilityHidden(preferences.windowLocked)
                .background(WindowLockFrameReporter(onChange: onLockControlChange))
            iconButton("slider.horizontal.3", label: "Настройки", action: onSettings)
                .disabled(preferences.windowLocked)
            Menu {
                Toggle("Показывать речь собеседника", isOn: $preferences.showTranscript)
                Toggle("Поверх других окон", isOn: $preferences.stayOnTop)
                Divider()
                if !answers.history.isEmpty {
                    Menu("Предыдущие ответы") {
                        ForEach(answers.history) { reply in
                            Button(String(reply.question.prefix(70))) { previous = reply }
                        }
                    }
                }
                Button("Очистить разговор") { previous = nil; assistant.clear() }
                    .disabled(answers.reply == nil && assistant.transcript.isEmpty)
                Divider()
                Button("Выйти из Dakt") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 24, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Действия и история ответов")
            .accessibilityLabel("Действия")
            .disabled(preferences.windowLocked)
            iconButton("minus", label: "Скрыть окно · \(preferences.hotKey.title)", action: onHide)
                .disabled(preferences.windowLocked)
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, 10)
        .background(WindowDragArea())
    }

    private func answer(_ reply: AnswerEngine.Reply, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 20) {
            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                if !compact { eyebrow(previous == nil ? "ВОПРОС СОБЕСЕДНИКА" : "ПРЕДЫДУЩИЙ ВОПРОС") }
                Text(reply.question)
                    .font(.system(size: compact ? 12 : max(13, preferences.fontSize - 4)))
                    .foregroundStyle(AssistantTheme.secondary)
                    .lineLimit(compact ? 1 : nil)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: compact ? 4 : 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle").font(.system(size: 10))
                        Text("МОЖНО ОТВЕТИТЬ").font(.system(size: 10, weight: .semibold)).tracking(1.1)
                    }
                    .foregroundStyle(AssistantTheme.accent)
                    Spacer()
                    if let latency = reply.latency {
                        Text(String(format: "%.1f с", latency))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AssistantTheme.secondary)
                            .help("От запроса к модели до первых слов ответа")
                    }
                    if !reply.text.isEmpty {
                        iconButton(copied ? "checkmark" : "doc.on.doc", label: copied ? "Скопировано" : "Скопировать ответ") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reply.text, forType: .string)
                            copied = true
                        }
                    }
                }
                if reply.text.isEmpty && reply.isStreaming {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Готовлю короткий ответ…").foregroundStyle(AssistantTheme.secondary)
                    }
                    .font(.system(size: 14))
                    .padding(.vertical, 8)
                } else {
                    Text(reply.text.isEmpty ? "Ответ пока не получен." : reply.text)
                        .font(.system(size: preferences.fontSize, weight: .regular))
                        .lineSpacing(6)
                        .foregroundStyle(Color(red: 0.94, green: 0.96, blue: 0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityLabel("Ответ: \(reply.text)")
                    if reply.isStreaming {
                        RoundedRectangle(cornerRadius: 2).fill(AssistantTheme.accent).frame(width: 18, height: 3)
                            .accessibilityLabel("Ответ продолжается")
                    }
                }
            }
            if previous != nil {
                Button("К текущему ответу") { previous = nil }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Circle().fill(AssistantTheme.accent).frame(width: 5, height: 5)
                Text("GPT‑6 LUNA  /  БЫСТРЫЙ ОТВЕТ")
                    .font(.system(size: 9, weight: .medium)).tracking(1)
                    .foregroundStyle(AssistantTheme.secondary)
            }
            Text(assistant.state == .listening ? "Слушаю вопросы.\nПомогу с ответом." : "Подсказка\nв нужный момент.")
                .font(.system(size: 27, weight: .medium))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Собеседник задаёт вопрос — здесь появляется короткий ответ. Слушаю только звук компьютера.")
                .font(.system(size: 13))
                .foregroundStyle(AssistantTheme.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if assistant.state == .idle {
                Button("Настроить подключение", action: onSettings)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 10)
    }

    private var speechStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                eyebrow("СОБЕСЕДНИК")
                Spacer()
                if assistant.canAnswerLatest {
                    Button(action: assistant.answerLatest) {
                        Label("Ответить", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AssistantTheme.accent)
                    .help("Ответить на последнюю реплику, даже если вопрос не распознан автоматически")
                }
            }
            Text(assistant.draft.isEmpty
                 ? (!assistant.captureStatus.isEmpty ? assistant.captureStatus : (assistant.transcript.last?.text ?? (assistant.state == .listening ? "Жду речь в системном звуке…" : "Включите прослушивание, когда начнётся разговор.")))
                 : assistant.draft)
                .font(.system(size: 12))
                .foregroundStyle(AssistantTheme.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .top) { Rectangle().fill(AssistantTheme.line).frame(height: 1) }
    }

    private func footer(compact: Bool) -> some View {
        HStack(spacing: 8) {
            AudioBars(activity: assistant.activity, active: assistant.state == .listening)
            Text(compact ? "Системный звук" : "Системный звук · микрофон выключен")
                .font(.system(size: 10))
                .foregroundStyle(AssistantTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Button(action: onSettings) {
                Image(systemName: "rectangle.on.rectangle.slash")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AssistantTheme.secondary)
            .help("Для скрытия подсказок демонстрируйте отдельное окно. Захват всего экрана может включать Dakt.")
            .accessibilityLabel("Настройки демонстрации экрана")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle") }
                .font(.system(size: 12))
            HStack(spacing: 16) {
                Button("Настройки", action: onSettings)
                if assistant.error == nil, answers.error != nil { Button("Повторить", action: assistant.retry) }
                if assistant.recovery == .dictation, preferences.whisperConfiguration.isComplete {
                    Button("Использовать WhisperX", action: assistant.useWhisperX)
                        .disabled(assistant.state != .idle)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            if let recovery = assistant.recovery {
                Button(recovery.title, action: assistant.openRecoverySettings)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(Color(red: 1, green: 0.77, blue: 0.57))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(AssistantTheme.secondary)
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 12)).frame(width: 28, height: 28) }
            .buttonStyle(.plain)
            .foregroundStyle(AssistantTheme.secondary)
            .help(label)
            .accessibilityLabel(label)
    }
}

private struct AudioBars: View {
    @ObservedObject var activity: AudioActivity
    let active: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5) { index in
                Capsule().fill(active ? AssistantTheme.accent : AssistantTheme.secondary.opacity(0.5))
                    .frame(width: 2, height: active ? 3 + CGFloat(min(1, activity.level * 3)) * CGFloat([7, 12, 16, 10, 5][index]) : 3)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityLabel(active ? "Системный звук активен" : "Прослушивание выключено")
    }
}

struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}

private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { }
}
