import AppKit
import SwiftUI

/// Нативная кнопка принимает первый клик и использует всю область 28 × 28 pt,
/// включая пустое место вокруг тонкого символа.
@MainActor
struct WindowHideButton: NSViewRepresentable {
    let action: () -> Void
    var shortcutTitle: String?

    final class Control: NSButton {
        var onHide: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        @objc func invoke() { onHide?() }
    }

    static func makeControl(action: @escaping () -> Void, shortcutTitle: String? = nil) -> Control {
        let button = Control(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.title = ""
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        button.contentTintColor = NSColor(srgbRed: 0.69, green: 0.73, blue: 0.75, alpha: 1)
        button.target = button
        button.action = #selector(Control.invoke)
        button.setAccessibilityLabel("Скрыть окно")
        configure(button, action: action, shortcutTitle: shortcutTitle)
        return button
    }

    private static func configure(_ button: Control, action: @escaping () -> Void, shortcutTitle: String?) {
        button.onHide = action
        button.toolTip = shortcutTitle.map { "Скрыть окно · " + $0 }
            ?? "Скрыть окно. Вернуть его можно горячей клавишей или через меню Dakt у часов."
    }

    func makeNSView(context: Context) -> Control {
        Self.makeControl(action: action, shortcutTitle: shortcutTitle)
    }

    func updateNSView(_ button: Control, context: Context) {
        Self.configure(button, action: action, shortcutTitle: shortcutTitle)
    }
}
