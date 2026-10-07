import AppKit

/// Совместимость со старыми средствами захвата. sharingType=.none не
/// гарантирует исключение из ScreenCaptureKit на современных macOS.
/// Интерфейс и README явно предлагают демонстрацию отдельного окна.
@MainActor
enum ScreenPrivacy {
    private static var hidden = true
    private static var observer: NSObjectProtocol?

    static func apply(hidden value: Bool) {
        hidden = value
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                              object: nil, queue: .main) { note in
                Task { @MainActor in
                    (note.object as? NSWindow)?.sharingType = hidden ? .none : .readOnly
                }
            }
        }
        for window in NSApp.windows { window.sharingType = hidden ? .none : .readOnly }
        let policy: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
}
