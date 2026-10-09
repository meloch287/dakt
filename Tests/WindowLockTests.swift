import AppKit
import SwiftUI
import XCTest
@testable import DaktRecorder

final class WindowLockTests: XCTestCase {
    @MainActor
    func testHideControlAcceptsFirstClickAndDoesNotStartWindowDragging() {
        _ = NSApplication.shared
        var hides = 0
        let button = WindowHideButton.makeControl(action: { hides += 1 })
        XCTAssertTrue(button.acceptsFirstMouse(for: nil))
        XCTAssertFalse(button.mouseDownCanMoveWindow)
        button.performClick(nil)
        XCTAssertEqual(hides, 1)
    }

    @MainActor
    func testLockWithoutAnAvailableUnlockControlKeepsInputEnabled() async {
        _ = NSApplication.shared
        let window = AssistantWindow()
        var recovered = false
        let interaction = WindowInteractionLock(window: window) { recovered = true }
        defer { window.close() }
        interaction.setLocked(true)
        XCTAssertFalse(window.isInteractionLocked)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(recovered)
    }

    @MainActor
    func testLockKeepsHostedWindowSizeAndUnlockButtonInsideAfterResize() async throws {
        _ = NSApplication.shared
        let preferences = AssistantPreferences(preview: true)
        let assistant = AssistantController(preferences: preferences, preview: true)
        let window = AssistantWindow()
        let interaction = WindowInteractionLock(window: window) { preferences.windowLocked = false }
        window.contentView = NSHostingView(rootView: AssistantView(
            assistant: assistant, answers: assistant.answers, preferences: preferences,
            onSettings: {}, onHide: {}, onLockControlChange: interaction.updateControlView,
            onHideControlChange: interaction.updateHideControlView, isPreview: true))
        window.orderFront(nil)
        defer { interaction.setLocked(false); window.close() }
        for size in [NSSize(width: 715, height: 519), NSSize(width: 280, height: 180),
                     NSSize(width: 1100, height: 720), NSSize(width: 300, height: 240)] {
            preferences.windowLocked = false
            interaction.setLocked(false)
            window.setContentSize(size)
            try await Task.sleep(nanoseconds: 200_000_000)
            let frame = window.frame
            preferences.windowLocked = true
            interaction.setLocked(true)
            try await Task.sleep(nanoseconds: 200_000_000)
            let unlock = try XCTUnwrap(interaction.unlockPanel)
            XCTAssertEqual(window.frame, frame, "Lock must not resize the hosted window")
            XCTAssertTrue(window.frame.contains(unlock.frame), "Unlock button must stay inside its window")
            XCTAssertTrue(unlock.isVisible)
            let hide = try XCTUnwrap(interaction.hidePanel)
            XCTAssertTrue(hide.isVisible)
            XCTAssertTrue(window.frame.contains(hide.frame))
            XCTAssertFalse(hide.frame.intersects(unlock.frame))
        }
    }

    @MainActor
    func testLockedWindowPassesInputAndCannotMoveOrResize() async {
        _ = NSApplication.shared
        let window = AssistantWindow()
        defer { window.close() }
        let frame = window.frame
        window.setInteractionLocked(true)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.frame, frame)
    }

    @MainActor
    func testUnlockRestoresNormalWindowInteraction() async {
        _ = NSApplication.shared
        let window = AssistantWindow()
        defer { window.close() }
        window.setInteractionLocked(true)
        window.setInteractionLocked(false)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(window.styleMask.contains(.resizable))
    }
}
