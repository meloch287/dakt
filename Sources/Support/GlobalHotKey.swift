import Foundation
import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш в терминах Carbon: код клавиши и маска модификаторов.
/// Хранится в настройках двумя числами и показывается человеку символами macOS.
struct KeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌘⇧Space быстро прячет и возвращает окно подсказок.
    static let `default` = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

    /// Сочетание из события клавиатуры. Без ⌘, ⌃ или ⌥ глобальная клавиша
    /// перехватывала бы обычный набор текста, поэтому такие не принимаем.
    init?(event: NSEvent) {
        var mask: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        guard mask & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        guard KeyCombo.name(forKeyCode: UInt32(event.keyCode)) != nil else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mask)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// «⌘⇧R» - в том порядке, в каком модификаторы рисует сама macOS.
    var title: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + (KeyCombo.name(forKeyCode: keyCode) ?? "?")
    }

    /// Имя клавиши по коду. Таблица покрывает буквы, цифры, F-клавиши и
    /// несколько служебных; остального для горячей клавиши не нужно.
    static func name(forKeyCode code: UInt32) -> String? {
        let table: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→"
        ]
        return table[Int(code)]
    }
}

/// Глобальная горячая клавиша: окно скрывается и появляется, даже когда
/// приложение не активно. Carbon-подход не требует разрешения на
/// управление компьютером.
private var hotKeyAction: (() -> Void)?

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var combo: KeyCombo?

    var isRegistered: Bool { hotKeyRef != nil }

    /// Перерегистрирует, если сочетание сменилось; повторный вызов с тем же
    /// сочетанием ничего не делает.
    func register(_ combo: KeyCombo, action: @escaping () -> Void) {
        if hotKeyRef != nil, self.combo == combo {
            hotKeyAction = action
            return
        }
        unregister()
        hotKeyAction = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { hotKeyAction?() }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        // 'DKRC' - произвольная подпись, чтобы не пересечься с чужими клавишами.
        let hotKeyID = EventHotKeyID(signature: OSType(0x444B5243), id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        self.combo = status == noErr ? combo : nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        hotKeyAction = nil
        combo = nil
    }
}
