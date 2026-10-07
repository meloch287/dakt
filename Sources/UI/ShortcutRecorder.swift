import SwiftUI
import AppKit

/// Поле для выбора горячей клавиши: нажали - и следующее сочетание с ⌘, ⌃
/// или ⌥ становится новым. Escape отменяет, «Сбросить» возвращает ⌘⇧Space.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    @State private var isListening = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isListening ? stopListening() : startListening()
            } label: {
                Text(isListening ? "Нажмите сочетание…" : combo.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isListening ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("Нажмите, затем введите новое сочетание. Escape - отмена.")

            if combo != .default {
                Button("Сбросить") { combo = .default }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .onDisappear { stopListening() }
    }

    private func startListening() {
        isListening = true
        // Локальный монитор видит только события своего приложения: ловим
        // нажатие, пока окно настроек активно, и не трогаем чужие программы.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stopListening()
                return nil
            }
            guard let picked = KeyCombo(event: event) else {
                NSSound.beep()
                return nil
            }
            combo = picked
            stopListening()
            return nil
        }
    }

    private func stopListening() {
        isListening = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
