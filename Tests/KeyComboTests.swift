import XCTest
import Carbon.HIToolbox
@testable import DaktRecorder

final class KeyComboTests: XCTestCase {
    func testDefaultHidesWindowWithCommandShiftSpace() {
        XCTAssertEqual(KeyCombo.default.title, "⇧⌘Space")
        XCTAssertEqual(KeyCombo.default.keyCode, UInt32(kVK_Space))
    }

    func testTitleOrdersModifiersLikeMacOS() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_1),
                             modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(combo.title, "⌃⌥⇧⌘1")
    }

    func testTitleForUnknownKeyIsQuestionMark() {
        let combo = KeyCombo(keyCode: 999, modifiers: UInt32(cmdKey))
        XCTAssertEqual(combo.title, "⌘?")
    }

    func testFunctionKeysAndSpaceHaveNames() {
        XCTAssertEqual(KeyCombo.name(forKeyCode: UInt32(kVK_F5)), "F5")
        XCTAssertEqual(KeyCombo.name(forKeyCode: UInt32(kVK_Space)), "Space")
        XCTAssertNil(KeyCombo.name(forKeyCode: UInt32(kVK_CapsLock)))
    }

    func testRoundTripsThroughInts() {
        let original = KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(optionKey | cmdKey))
        let restored = KeyCombo(keyCode: UInt32(Int(original.keyCode)), modifiers: UInt32(Int(original.modifiers)))
        XCTAssertEqual(original, restored)
    }

    @MainActor
    func testEventWithoutCommandLikeModifierIsRejected() throws {
        // Только Shift: такое сочетание перехватывало бы обычный набор текста.
        let shiftOnly = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
                                                       timestamp: 0, windowNumber: 0, context: nil,
                                                       characters: "R", charactersIgnoringModifiers: "r",
                                                       isARepeat: false, keyCode: UInt16(kVK_ANSI_R)))
        XCTAssertNil(KeyCombo(event: shiftOnly))

        let withCommand = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                         modifierFlags: [.command, .option],
                                                         timestamp: 0, windowNumber: 0, context: nil,
                                                         characters: "r", charactersIgnoringModifiers: "r",
                                                         isARepeat: false, keyCode: UInt16(kVK_ANSI_R)))
        let combo = try XCTUnwrap(KeyCombo(event: withCommand))
        XCTAssertEqual(combo.title, "⌥⌘R")
    }
}
