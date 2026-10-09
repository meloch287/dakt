import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var preferences: AssistantPreferences!
    private var assistant: AssistantController!
    private var panel: AssistantWindow!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var listenItem: NSMenuItem?
    private var lockItem: NSMenuItem?
    private var interactionLock: WindowInteractionLock!
    private let hotKey = GlobalHotKey()
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        var preview = false
        #if DEBUG
        preview = CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--render-previews")
        #endif
        preferences = AssistantPreferences(preview: preview)
        assistant = AssistantController(preferences: preferences, preview: preview)
        panel = AssistantWindow()
        panel.delegate = self
        interactionLock = WindowInteractionLock(window: panel, onHide: { [weak self] in self?.hideWindow() }) {
            [weak self] in self?.preferences.windowLocked = false
        }
        panel.contentView = NSHostingView(rootView: AssistantView(
            assistant: assistant, answers: assistant.answers, preferences: preferences,
            onSettings: { [weak self] in self?.showSettings() },
            onHide: { [weak self] in self?.hideWindow() },
            onLockControlChange: { [weak self] view in self?.interactionLock.updateControlView(view) },
            onHideControlChange: { [weak self] view in self?.interactionLock.updateHideControlView(view) }, isPreview: preview))
        if !preview { panel.setFrameAutosaveName("DaktAssistantWindow") }
        applyWindowPreferences()
        buildMenu()
        showWindow()
        #if DEBUG
        if preview { assistant.loadExample() }
        #endif
        if !preview {
            registerShortcut()
            preferences.$hotKey.removeDuplicates().dropFirst().receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.registerShortcut() }.store(in: &subscriptions)
        }
        preferences.$stayOnTop.combineLatest(preferences.$privateMode, preferences.$windowLocked)
            .removeDuplicates { $0 == $1 }.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyWindowPreferences() }.store(in: &subscriptions)
        assistant.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.listenItem?.title = state == .idle ? "Слушать системный звук" : "Пауза"
            self?.statusItem?.button?.toolTip = "Dakt · \(state.title)"
        }.store(in: &subscriptions)
        // Явный импорт из командной строки используется и при передаче резюме
        // из внешнего приложения. Файл читается только по указанному пути.
        if !preview, let index = CommandLine.arguments.firstIndex(of: "--import-resume"),
           CommandLine.arguments.count > index + 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            var displayName: String?
            if let nameIndex = CommandLine.arguments.firstIndex(of: "--resume-name"), CommandLine.arguments.count > nameIndex + 1 {
                displayName = CommandLine.arguments[nameIndex + 1]
            }
            showSettings()
            Task { @MainActor in await assistant.meetingContext.importResume(from: url, displayName: displayName) }
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            Task { @MainActor in
                do {
                    try await AssistantPreviewRenderer.render(panel: panel, assistant: assistant, preferences: preferences,
                                                              interactionLock: interactionLock, to: destination)
                    NSApp.terminate(nil)
                } catch {
                    print("Preview failed: \(error)")
                    exit(1)
                }
            }
        }
        #endif
    }

    private func applyWindowPreferences() {
        let wasLocked = panel?.isInteractionLocked ?? false
        panel?.level = preferences.stayOnTop || preferences.windowLocked ? .floating : .normal
        ScreenPrivacy.apply(hidden: preferences.privateMode)
        interactionLock?.setLocked(preferences.windowLocked)
        lockItem?.title = preferences.windowLocked ? "Разблокировать окно" : "Закрепить окно и пропускать клики"
        lockItem?.state = preferences.windowLocked ? .on : .off
        if preferences.windowLocked && !wasLocked {
            // Клавиатура должна вернуться к приложению под подсказкой.
            if NSApp.isActive { NSApp.deactivate() }
        } else if wasLocked && !preferences.windowLocked && panel.isVisible {
            showWindow()
        }
    }

    private func registerShortcut() {
        hotKey.register(preferences.hotKey) { [weak self] in
            Task { @MainActor in self?.toggleWindow() }
        }
        if !hotKey.isRegistered { assistant.error = "Горячая клавиша занята. Выберите другую в настройках окна." }
    }

    @objc private func toggleWindow() {
        if panel.isVisible || settingsWindow?.isVisible == true { hideWindow() }
        else { showWindow() }
    }

    @objc private func showWindow() {
        if preferences.windowLocked { panel.orderFrontRegardless() }
        else {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
        interactionLock.synchronize()
        updateMeterVisibility()
    }

    @objc private func restoreWindow() {
        // Явное открытие из Dock или меню всегда возвращает управление,
        // даже если отдельная кнопка разблокировки оказалась недоступна.
        preferences.windowLocked = false
        interactionLock.setLocked(false)
        showWindow()
    }

    @objc private func hideWindow() {
        assistant.activity.setVisible(false)
        for window in NSApp.windows { window.orderOut(nil) }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateMeterVisibility() }

    private func updateMeterVisibility() {
        assistant.activity.setVisible(panel.isVisible && panel.occlusionState.contains(.visible))
    }

    @objc private func toggleListening() { assistant.toggle() }
    @objc private func toggleLock() { preferences.windowLocked.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 680),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Настройки Dakt"
            window.minSize = NSSize(width: 400, height: 440)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AssistantSettingsView(preferences: preferences, assistant: assistant))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.sharingType = preferences.privateMode ? .none : .readOnly
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Dakt")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        for (title, action) in [("Показать Dakt", #selector(restoreWindow)),
                                ("Скрыть Dakt", #selector(hideWindow)),
                                ("Слушать системный звук", #selector(toggleListening)),
                                ("Закрепить окно и пропускать клики", #selector(toggleLock)),
                                ("Настройки…", #selector(showSettings))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
            if action == #selector(toggleListening) { listenItem = entry }
            if action == #selector(toggleLock) { lockItem = entry }
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item

        // Нативное меню сохраняет стандартные copy/paste и ⌘, в настройках.
        let mainMenu = NSMenu()
        let applicationMenu = NSMenu()
        let root = NSMenuItem()
        root.submenu = applicationMenu
        mainMenu.addItem(root)
        let settings = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(settings)
        let exit = NSMenuItem(title: "Выйти из Dakt", action: #selector(quit), keyEquivalent: "q")
        exit.target = self
        applicationMenu.addItem(exit)
        let edit = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Правка")
        for (title, selector, key) in [("Вырезать", "cut:", "x"), ("Копировать", "copy:", "c"),
                                       ("Вставить", "paste:", "v"), ("Выбрать всё", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        edit.submenu = editMenu
        mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { hideWindow(); return false }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let assistant, assistant.state != .idle else { return .terminateNow }
        Task {
            await assistant.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) { hotKey.unregister() }
}
