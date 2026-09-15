import XCTest
import AppKit
@testable import Zoomies

final class KeyCommandInterpreterTests: XCTestCase {
    // Carbon virtual key codes used by interpretKeyCommand.
    private let returnKey: UInt16 = 36
    private let numpadEnterKey: UInt16 = 76
    private let deleteKey: UInt16 = 51
    private let escapeKey: UInt16 = 53
    private let tabKey: UInt16 = 48

    func testReturnAlone() {
        XCTAssertEqual(label(for: returnKey, flags: []), "enter")
    }

    func testCommandReturn() {
        XCTAssertEqual(label(for: returnKey, flags: [.command]), "commandEnter")
    }

    func testCommandShiftReturn() {
        XCTAssertEqual(label(for: returnKey, flags: [.command, .shift]), "commandShiftEnter")
    }

    func testCommandDelete() {
        XCTAssertEqual(label(for: deleteKey, flags: [.command]), "commandBackspace")
    }

    func testDeleteAloneIsNil() {
        XCTAssertEqual(label(for: deleteKey, flags: []), "nil")
    }

    func testEscape() {
        XCTAssertEqual(label(for: escapeKey, flags: []), "escape")
    }

    func testTab() {
        XCTAssertEqual(label(for: tabKey, flags: []), "tab")
    }

    func testShiftTab() {
        XCTAssertEqual(label(for: tabKey, flags: [.shift]), "shiftTab")
    }

    func testNumpadEnterMatchesReturn() {
        XCTAssertEqual(label(for: numpadEnterKey, flags: []), "enter")
    }

    func testCommandNumpadEnterMatchesCommandReturn() {
        XCTAssertEqual(label(for: numpadEnterKey, flags: [.command]), "commandEnter")
    }

    func testNoteNumpadEnterSaves() {
        XCTAssertEqual(noteLabel(for: numpadEnterKey, flags: []), "enter")
    }

    func testNotePlainEnterSaves() {
        XCTAssertEqual(noteLabel(for: returnKey, flags: []), "enter")
    }

    func testNoteShiftEnterFallsThroughForNewline() {
        XCTAssertNil(noteCommand(for: returnKey, flags: [.shift]))
        XCTAssertNil(noteCommand(for: numpadEnterKey, flags: [.shift]))
    }

    func testNoteCommandEnterCopies() {
        XCTAssertEqual(noteLabel(for: returnKey, flags: [.command]), "commandEnter")
        XCTAssertEqual(noteLabel(for: numpadEnterKey, flags: [.command]), "commandEnter")
    }

    func testNoteCommandShiftEnterCopies() {
        // Command wins over Shift in the note box: no newline, Copy+Save.
        XCTAssertEqual(noteLabel(for: returnKey, flags: [.command, .shift]), "commandEnter")
        XCTAssertEqual(noteLabel(for: numpadEnterKey, flags: [.command, .shift]), "commandEnter")
    }

    // MARK: - Helpers

    private func label(for keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
        return label(interpretKeyCommand(from: event))
    }

    private func noteCommand(for keyCode: UInt16, flags: NSEvent.ModifierFlags) -> KeyCommand? {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
        return interpretNoteKeyCommand(from: event)
    }

    private func noteLabel(for keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        label(noteCommand(for: keyCode, flags: flags))
    }

    private func label(_ command: KeyCommand?) -> String {
        guard let command else { return "nil" }
        switch command {
        case .enter: return "enter"
        case .commandEnter: return "commandEnter"
        case .commandShiftEnter: return "commandShiftEnter"
        case .commandBackspace: return "commandBackspace"
        case .escape: return "escape"
        case .tab: return "tab"
        case .shiftTab: return "shiftTab"
        }
    }
}
