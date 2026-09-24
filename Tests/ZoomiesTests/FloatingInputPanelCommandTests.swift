import AppKit
import XCTest
@testable import Zoomies

final class FloatingInputPanelCommandTests: XCTestCase {
    private final class TextView: NSTextView {
        let history = UndoManager()
        override var undoManager: UndoManager? { history }
    }
    private final class Value: NSObject {
        var number = 0
        func set(_ number: Int, using history: UndoManager) {
            let previous = self.number
            history.registerUndo(withTarget: self) { $0.set(previous, using: history) }
            self.number = number
        }
    }
    private func event(_ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: 6)!
    }
    func testCopyPasteCutAndSelectAllRouteOnlyExactCommandModifier() {
        var sent: [Selector] = []
        let panel = FloatingInputPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), sendEditingAction: { selector, _ in
            sent.append(selector); return true
        })
        for (chars, selector) in [("c", #selector(NSText.copy(_:))), ("v", #selector(NSText.paste(_:))),
                                  ("x", #selector(NSText.cut(_:))), ("a", #selector(NSText.selectAll(_:)))] {
            XCTAssertTrue(panel.performKeyEquivalent(with: event(chars.uppercased(), .command)))
            XCTAssertEqual(sent.last, selector)
            let count = sent.count
            _ = panel.performKeyEquivalent(with: event(chars, [.command, .shift]))
            XCTAssertEqual(sent.count, count)
        }
        XCTAssertFalse(panel.isVisible)
    }

    func testUndoRedoUsesActualFirstResponderHistory() {
        let panel = FloatingInputPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), sendEditingAction: { _, _ in
            XCTFail("Undo must use the text view's history"); return false
        })
        let text = TextView(frame: panel.contentView!.bounds)
        panel.contentView?.addSubview(text)
        XCTAssertTrue(panel.makeFirstResponder(text))
        let value = Value()
        text.history.beginUndoGrouping()
        value.set(7, using: text.history)
        text.history.endUndoGrouping()
        XCTAssertTrue(panel.performKeyEquivalent(with: event("z", .command)))
        XCTAssertEqual(value.number, 0)
        XCTAssertTrue(panel.performKeyEquivalent(with: event("z", [.command, .shift])))
        XCTAssertEqual(value.number, 7)
        XCTAssertFalse(panel.isVisible)
    }
}
