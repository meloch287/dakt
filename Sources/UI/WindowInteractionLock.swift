import AppKit
import SwiftUI

/// Основное окно полностью пропускает ввод. Единственное исключение —
/// маленькое дочернее окно с замком: оно позволяет снять блокировку без
/// перехвата мыши, глобальных мониторов и разрешения на управление компьютером.
@MainActor
final class WindowInteractionLock {
    private weak var window: AssistantWindow?
    private weak var controlView: NSView?
    private let onUnlock: () -> Void
    private(set) var unlockPanel: NSPanel?
    private var observers: [NSObjectProtocol] = []

    var controlRect: CGRect {
        guard let window, let controlView, controlView.window === window else { return .zero }
        return controlView.convert(controlView.bounds, to: nil)
    }

    private var unlockFrame: CGRect? {
        guard let window else { return nil }
        let rect = controlRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let frame = window.convertToScreen(rect)
        return window.frame.contains(frame) ? frame : nil
    }

    init(window: AssistantWindow, onUnlock: @escaping () -> Void) {
        self.window = window
        self.onUnlock = onUnlock
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.synchronize() }
            })
        }
    }

    func updateControlView(_ view: NSView) {
        controlView = view
        synchronize()
    }

    func setLocked(_ locked: Bool) {
        guard !locked || unlockFrame != nil else {
            window?.setInteractionLocked(false)
            unlockPanel?.orderOut(nil)
            onUnlock()
            return
        }
        window?.setInteractionLocked(locked)
        synchronize()
    }

    func synchronize() {
        guard let window, window.isInteractionLocked, window.isVisible else {
            unlockPanel?.orderOut(nil)
            return
        }
        guard let frame = unlockFrame else {
            // Если layout ещё не готов или кнопка исчезла, окно остаётся
            // управляемым: блокировать ввод без доступного замка нельзя.
            setLocked(false)
            onUnlock()
            return
        }
        if unlockPanel == nil {
            let panel = UnlockPanel(contentRect: .zero,
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovable = false
            panel.isExcludedFromWindowsMenu = true
            panel.contentView = UnlockHostingView(rootView: WindowLockButton(locked: true, action: onUnlock))
            window.addChildWindow(panel, ordered: .above)
            unlockPanel = panel
        }
        guard let panel = unlockPanel else { return }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.level = window.level
        panel.sharingType = window.sharingType
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

private final class UnlockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class UnlockHostingView: NSHostingView<WindowLockButton> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct WindowLockButton: View {
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(locked ? AssistantTheme.accent : AssistantTheme.secondary)
                .background(locked ? AssistantTheme.accent.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(locked
              ? "Разблокировать окно. Сейчас клики проходят к приложениям под ним."
              : "Закрепить окно и пропускать клики к приложениям под ним")
        .accessibilityLabel(locked ? "Разблокировать окно" : "Закрепить окно и пропускать клики")
        .accessibilityValue(locked ? "Закреплено" : "Не закреплено")
    }
}

/// Сохраняем саму точку привязки, а не снимок её координат. При изменении
/// размера окна SwiftUI двигает предков Marker без изменения его frame.
/// Координаты пересчитываются из живой иерархии при каждом показе замка.
struct WindowLockFrameReporter: NSViewRepresentable {
    let onChange: (NSView) -> Void

    final class Marker: NSView {
        var onChange: ((NSView) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func layout() { super.layout(); report() }
        override func setFrameOrigin(_ point: NSPoint) { super.setFrameOrigin(point); report() }
        override func setFrameSize(_ size: NSSize) { super.setFrameSize(size); report() }

        func report() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onChange?(self)
            }
        }
    }

    func makeNSView(context: Context) -> Marker {
        let marker = Marker()
        marker.onChange = onChange
        return marker
    }

    func updateNSView(_ marker: Marker, context: Context) {
        marker.onChange = onChange
        marker.report()
    }
}
