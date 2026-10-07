import AppKit

final class AssistantWindow: NSPanel {
    private(set) var isInteractionLocked = false
    override var canBecomeKey: Bool { !isInteractionLocked }
    override var canBecomeMain: Bool { !isInteractionLocked }

    func setInteractionLocked(_ locked: Bool) {
        guard isInteractionLocked != locked else { return }
        let savedFrame = frame
        isInteractionLocked = locked
        ignoresMouseEvents = locked
        isMovable = !locked
        isMovableByWindowBackground = !locked
        if locked { styleMask.remove(.resizable) }
        else { styleMask.insert(.resizable) }
        // Изменение styleMask не должно сдвигать закреплённое окно.
        setFrame(savedFrame, display: true)
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Dakt"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        contentMinSize = NSSize(width: 280, height: 180)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        center()
    }
}
