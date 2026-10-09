#if DEBUG
import SwiftUI
import AppKit

/// Снимки настоящих views с фикстурами, без захвата аудио, ключей и сети.
@MainActor
enum AssistantPreviewRenderer {
    static func render(panel: AssistantWindow, assistant: AssistantController,
                       preferences: AssistantPreferences, interactionLock: WindowInteractionLock, to folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, size) in [("answer", NSSize(width: 620, height: 500)),
                             ("minimum", NSSize(width: 280, height: 180)),
                             ("compact", NSSize(width: 300, height: 240)),
                             ("wide", NSSize(width: 1100, height: 720)),
                             ("resized", NSSize(width: 715, height: 519))] {
            panel.setContentSize(size)
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 250_000_000)
            try snapshot(panel.contentView!, to: folder.appendingPathComponent("\(name).png"))
            try await verifyLockCycle(panel: panel, preferences: preferences, interaction: interactionLock,
                                      folder: folder, name: name)
        }
        panel.setContentSize(NSSize(width: 620, height: 500))
        try await Task.sleep(nanoseconds: 250_000_000)
        try await verifyLockCycle(panel: panel, preferences: preferences, interaction: interactionLock,
                                  folder: folder, name: "reopen", viaReopen: true)
        for (name, locked, offset, inactive) in [("unlocked-edge", false, CGFloat(-10), false),
                                                 ("unlocked-center", false, CGFloat(0), false),
                                                 ("unlocked-inactive", false, CGFloat(-10), true),
                                                 ("locked-center", true, CGFloat(0), true),
                                                 ("locked-edge", true, CGFloat(-10), true)] {
            try await verifyHideButton(panel: panel, assistant: assistant, preferences: preferences,
                                       interaction: interactionLock, name: name, locked: locked, offset: offset, inactive: inactive)
        }
        panel.setContentSize(NSSize(width: 280, height: 240))
        try await verifyHideButton(panel: panel, assistant: assistant, preferences: preferences,
                                   interaction: interactionLock, name: "compact-locked-edge", locked: true, offset: -10, inactive: true)
        try await renderVocabularyExamples(to: folder)
        panel.setContentSize(NSSize(width: 620, height: 500))
        assistant.answers.showExample(queued: 2)
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(panel.contentView!, to: folder.appendingPathComponent("answer-queue.png"))
        assistant.answers.showExample(waitingForNext: true)
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(panel.contentView!, to: folder.appendingPathComponent("complete-answer-while-waiting.png"))
        await assistant.stop()
        assistant.clear()
        panel.setContentSize(NSSize(width: 500, height: 420))
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(panel.contentView!, to: folder.appendingPathComponent("idle.png"))
        assistant.reportSpeechFailure(SpeechFailure(NSError(domain: "kLSRErrorDomain", code: 201)))
        panel.setContentSize(NSSize(width: 300, height: 360))
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(panel.contentView!, to: folder.appendingPathComponent("dictation-disabled.png"))
        assistant.clear()
        let settings = NSHostingView(rootView: AssistantSettingsView(preferences: preferences, assistant: assistant))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 820),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = settings
        window.orderFront(nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(settings, to: folder.appendingPathComponent("settings.png"))
        if let scroll = firstScrollView(in: settings), let document = scroll.documentView {
            document.scroll(NSPoint(x: 0, y: 700))
            try await Task.sleep(nanoseconds: 250_000_000)
            try snapshot(settings, to: folder.appendingPathComponent("question-pause.png"))
            window.setContentSize(NSSize(width: 380, height: 820))
            try await Task.sleep(nanoseconds: 250_000_000)
            try snapshot(settings, to: folder.appendingPathComponent("question-pause-narrow.png"))
            window.setContentSize(NSSize(width: 480, height: 820))
            document.scroll(.zero)
        }
        // Только вымышленные данные: реальные резюме в снимки не попадают.
        preferences.resumeName = "Пример резюме — Python Backend.pdf"
        preferences.resumeText = "Алексей — Python backend-разработчик. FastAPI, PostgreSQL, Redis. Разрабатывал сервис обработки заявок и фоновые задачи."
        preferences.meetingDetails = "Техническое собеседование на backend-разработчика"
        preferences.context = """
        ## Профиль
        Python backend-разработчик: FastAPI, PostgreSQL, Redis.

        ## Самопрезентация
        Я разрабатываю серверные приложения на Python. В последнем проекте работал над обработкой заявок и фоновыми задачами.

        ## Что уточнить
        Компания, команда и задачи роли пока не указаны.
        """
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(settings, to: folder.appendingPathComponent("resume-context.png"))
        window.setContentSize(NSSize(width: 380, height: 820))
        try await Task.sleep(nanoseconds: 250_000_000)
        try snapshot(settings, to: folder.appendingPathComponent("resume-context-narrow.png"))
        window.orderOut(nil)
        panel.setContentSize(NSSize(width: 620, height: 500))
        panel.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        // Проверяем настоящий hit-testing кнопки под прозрачным titlebar.
        let view = panel.contentView!
        let point = view.convert(NSPoint(x: view.bounds.width - 28,
                                        y: view.isFlipped ? 24 : view.bounds.height - 24), to: nil)
        click(window: panel, at: point)
        try await Task.sleep(nanoseconds: 250_000_000)
        guard !panel.isVisible else { throw RecorderError.message("Кнопка скрытия не получила клик.") }
        print("Hide button: native mouse event passed")
        print("Native previews: \(folder.path)")
        print("Window: resizable=\(panel.styleMask.contains(.resizable)), opaque=\(panel.isOpaque), minimum=\(panel.contentMinSize)")
    }

    private static func renderVocabularyExamples(to folder: URL) async throws {
        let preferences = AssistantPreferences(preview: true)
        preferences.speechTerms = "gRPC, Kafka, ClickHouse"
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.receive("Что такое IP?")
        let answers = AnswerEngine { _, _, _, _ in
            "API: интерфейс, через который программы обращаются друг к другу.\n\nIP: адрес устройства в сети, по которому к нему доставляются пакеты."
        }
        answers.ask("Что такое IP?", recent: [], config: LunaConfiguration())
        let window = AssistantWindow()
        let interaction = WindowInteractionLock(window: window) { preferences.windowLocked = false }
        window.contentView = NSHostingView(rootView: AssistantView(
            assistant: assistant, answers: answers, preferences: preferences,
            onSettings: {}, onHide: {}, onLockControlChange: interaction.updateControlView,
            onHideControlChange: interaction.updateHideControlView, isPreview: true))
        window.orderFrontRegardless()
        defer { answers.cancel(); window.close() }
        for (name, size) in [("api-ip", NSSize(width: 620, height: 420)),
                             ("api-ip-compact", NSSize(width: 280, height: 240))] {
            window.setContentSize(size)
            try await Task.sleep(nanoseconds: 250_000_000)
            try snapshot(window.contentView!, to: folder.appendingPathComponent("\(name).png"))
        }
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = firstScrollView(in: child) { return scroll }
        }
        return nil
    }

    private static func verifyHideButton(panel: AssistantWindow, assistant: AssistantController,
                                         preferences: AssistantPreferences, interaction: WindowInteractionLock,
                                         name: String, locked: Bool, offset: CGFloat, inactive: Bool) async throws {
        _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: panel.isVisible)
        try await Task.sleep(nanoseconds: 250_000_000)
        preferences.windowLocked = locked
        try await Task.sleep(nanoseconds: 250_000_000)
        if inactive { NSApp.deactivate() }
        let state = assistant.state
        let host = panel.contentView!
        let point = host.convert(NSPoint(x: host.bounds.width - 28 + offset,
                                        y: host.isFlipped ? 24 + offset : host.bounds.height - 24 + offset), to: nil)
        let screen = panel.convertPoint(toScreen: point)
        let targetNumber = NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0)
        guard let target = NSApp.windows.first(where: { $0.windowNumber == targetNumber }) else {
            print("Hide geometry \(name): point=\(screen), control=\(String(describing: interaction.hidePanel?.frame)), inside=\(interaction.hidePanel?.frame.contains(screen) ?? false)")
            throw RecorderError.message("Клик по «−» уходит в другое приложение: \(name).")
        }
        click(window: target, at: target.convertPoint(fromScreen: screen))
        try await Task.sleep(nanoseconds: 250_000_000)
        interaction.synchronize()
        guard !panel.isVisible, interaction.unlockPanel?.isVisible != true, interaction.hidePanel?.isVisible != true,
              assistant.state == state else {
            throw RecorderError.message("Кнопка «−» не скрыла окно или изменила прослушивание: \(name).")
        }
        print("Hide \(name): click hides the window and keeps listening unchanged")
        // Этот же selector вызывает глобальная горячая клавиша. Возврат
        // должен сохранить замок и вновь показать обе доступные кнопки.
        guard NSApp.sendAction(Selector(("toggleWindow")), to: NSApp.delegate, from: nil) else {
            throw RecorderError.message("Не найдено действие горячей клавиши.")
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        guard panel.isVisible, preferences.windowLocked == locked,
              !locked || (interaction.hidePanel?.isVisible == true && interaction.unlockPanel?.isVisible == true) else {
            throw RecorderError.message("Возврат окна не восстановил управление: \(name).")
        }
        _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    private static func verifyLockCycle(panel: AssistantWindow, preferences: AssistantPreferences,
                                        interaction: WindowInteractionLock, folder: URL, name: String,
                                        viaReopen: Bool = false) async throws {
        let frame = panel.frame
        let rect = interaction.controlRect
        guard rect.width > 0, let host = panel.contentView else {
            throw RecorderError.message("Не найдена кнопка закрепления: \(name).")
        }
        click(window: panel, at: NSPoint(x: rect.midX, y: rect.midY))
        try await Task.sleep(nanoseconds: 350_000_000)
        guard preferences.windowLocked, panel.ignoresMouseEvents, !panel.isMovable,
              panel.frame == frame, let unlock = interaction.unlockPanel,
              unlock.isVisible, !unlock.ignoresMouseEvents, panel.frame.contains(unlock.frame),
              unlock.frame == panel.convertToScreen(interaction.controlRect) else {
            throw RecorderError.message("Закрепление, размер или положение замка неверны: \(name).")
        }
        let center = NSPoint(x: unlock.frame.midX, y: unlock.frame.midY)
        guard NSWindow.windowNumber(at: center, belowWindowWithWindowNumber: 0) == unlock.windowNumber else {
            throw RecorderError.message("На месте замка другое окно: \(name).")
        }
        try snapshot(host, to: folder.appendingPathComponent("locked-\(name).png"))
        if let control = unlock.contentView {
            try snapshot(control, to: folder.appendingPathComponent("unlock-control.png"))
        }
        if let control = interaction.hidePanel?.contentView {
            try snapshot(control, to: folder.appendingPathComponent("hide-control.png"))
        }
        if viaReopen {
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true)
        } else {
            click(window: unlock, at: NSPoint(x: unlock.frame.width / 2, y: unlock.frame.height / 2))
        }
        try await Task.sleep(nanoseconds: 350_000_000)
        guard !preferences.windowLocked, !panel.ignoresMouseEvents, panel.isMovable,
              panel.styleMask.contains(.resizable), !unlock.isVisible, panel.frame == frame else {
            throw RecorderError.message("Разблокировка не восстановила управление и размер: \(name).")
        }
        print("Lock/unlock \(name): frame preserved, unlock visible and reachable, input restored")
    }

    private static func click(window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw RecorderError.message("Не удалось снять view.")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RecorderError.message("Не удалось сохранить PNG.")
        }
        try png.write(to: url)
    }
}
#endif
