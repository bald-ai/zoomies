import AppKit
import Carbon
import XCTest
@testable import Zoomies

final class CanvasShortcutContractTests: XCTestCase {
    private func event(_ key: UInt16, _ flags: NSEvent.ModifierFlags = [], _ chars: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                        isARepeat: false, keyCode: key)!
    }

    func testEditingShortcutsAndFinalActionsKeepTheirDistinctContracts() {
        let canvas = EditorCanvasView(image: TestSupport.solidImage())
        let cases: [(UInt16, NSEvent.ModifierFlags, String, EditorCanvasView.KeyCommand)] = [
            (24, .command, "=", .zoomIn), (24, .command, "+", .zoomIn),
            (27, .command, "-", .zoomOut), (29, .command, "0", .zoomReset),
            (6, .command, "z", .undo), (6, [.command, .shift], "Z", .redo),
            (8, .command, "c", .copyToClipboard), (7, .command, "x", .cutSelectionToClipboard),
            (9, .command, "v", .pasteSelectionInCanvas), (51, .option, "", .clear),
            (36, [], "", .finalAction(.saveOnly)), (76, [], "", .finalAction(.saveOnly)),
            (36, .command, "", .finalAction(.copyAndSave)), (76, .command, "", .finalAction(.copyAndSave)),
            (51, .command, "", .finalAction(.copyAndDelete)), (53, [], "", .finalAction(.deleteOnly)),
            (48, .shift, "", .backToNote)
        ]
        for (key, flags, chars, expected) in cases {
            var received: [EditorCanvasView.KeyCommand] = []
            canvas.onKeyCommand = { received.append($0) }
            canvas.keyDown(with: event(key, flags, chars))
            XCTAssertEqual(received, [expected], "key \(key), flags \(flags)")
        }
    }

    func testPhysicalToolKeysRespectModifiersAndCapsLock() {
        let canvas = EditorCanvasView(image: TestSupport.solidImage())
        let keys: [(UInt16, EditorTool)] = [(13, .pen), (2, .line), (0, .arrow), (15, .rectangle),
            (14, .ellipse), (17, .text), (3, .marker), (1, .selection)]
        for (key, tool) in keys {
            var received: [EditorCanvasView.KeyCommand] = []
            canvas.onKeyCommand = { received.append($0) }
            canvas.keyDown(with: event(key, .capsLock, "other layout"))
            XCTAssertEqual(received, [.selectTool(tool)])
            for flag: NSEvent.ModifierFlags in [.shift, .control, .option, .command] {
                received = []
                canvas.keyDown(with: event(key, flag, ""))
                XCTAssertTrue(received.isEmpty)
            }
        }
    }

    func testPickerCommandsHavePriorityAndToggleDoesNotCloseOpenPicker() {
        let canvas = EditorCanvasView(image: TestSupport.solidImage())
        var received: [EditorCanvasView.KeyCommand] = []
        canvas.onKeyCommand = { received.append($0) }
        canvas.keyDown(with: event(UInt16(kVK_ANSI_K)))
        XCTAssertEqual(received, [.toggleColorPicker])
        canvas.isColorPickerOpen = true
        received = []
        canvas.keyDown(with: event(UInt16(kVK_ANSI_K)))
        XCTAssertTrue(received.isEmpty)
        let cases: [(UInt16, [EditorCanvasView.KeyCommand])] = [
            (18, [.selectColor(index: 0), .colorPickerClose]),
            (22, [.selectColor(index: 5), .colorPickerClose]),
            (83, [.selectColor(index: 0), .colorPickerClose]),
            (88, [.selectColor(index: 5), .colorPickerClose]),
            (123, [.colorPickerMove(direction: -1)]), (124, [.colorPickerMove(direction: 1)]),
            (36, [.colorPickerSelect]), (76, [.colorPickerSelect]), (53, [.colorPickerClose]),
            (12, [.cycleColor])
        ]
        for (key, expected) in cases {
            received = []
            canvas.keyDown(with: event(key))
            XCTAssertEqual(received, expected)
        }
    }
}
