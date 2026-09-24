import AppKit
import XCTest
@testable import Zoomies

final class RenameInputContractTests: XCTestCase {
    private func field(in view: NSView?) -> CommandAwareTextField? {
        if let field = view as? CommandAwareTextField { return field }
        for child in view?.subviews ?? [] { if let match = field(in: child) { return match } }
        return nil
    }
    private func label(_ action: RenamePanelAction) -> String {
        switch action {
        case .save(let name): return "save:\(name)"
        case .copyAndSave(let name): return "copy-save:\(name)"
        case .copyAndDelete(let name): return "copy-delete:\(name)"
        case .delete: return "delete"
        case .close: return "close"
        case .goToNote(let name): return "note:\(name)"
        }
    }
    func testRenameInputSanitizesAndRoutesEverySupportedCommand() throws {
        let controller = RenamePanelController(initialFilename: "shot.png")
        let input = try XCTUnwrap(field(in: controller.window?.contentView))
        var received: [String] = []
        controller.onAction = { received.append(self.label($0)) }
        let cases: [(KeyCommand, String)] = [(.enter,"save:new"), (.commandEnter,"copy-save:new"),
            (.commandShiftEnter,"copy-save:new"), (.commandBackspace,"copy-delete:new"),
            (.escape,"delete"), (.tab,"note:new")]
        for (command, expected) in cases {
            input.stringValue = "  new.png  "
            input.keyCommandHandler?(command)
            XCTAssertEqual(received.last, expected)
            XCTAssertEqual(input.stringValue, "new")
        }
        let count = received.count
        input.keyCommandHandler?(.shiftTab)
        XCTAssertEqual(received.count, count)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testVideoAndNoteRestrictionsIgnoreUnsupportedNavigationAndDeletion() throws {
        let controller = RenamePanelController(initialFilename: "note.md", escapeKeyDeletesFile: false,
                                               showsCopyAndDiscard: false, allowsNoteNavigation: false)
        let input = try XCTUnwrap(field(in: controller.window?.contentView))
        var received: [String] = []
        controller.onAction = { received.append(self.label($0)) }
        input.keyCommandHandler?(.commandBackspace)
        input.keyCommandHandler?(.tab)
        XCTAssertTrue(received.isEmpty)
        input.keyCommandHandler?(.escape)
        XCTAssertEqual(received, ["close"])
    }

    func testFieldEditorSelectorFallbackDispatchesCommandsAndRejectsUnknownSelectors() {
        // Initialize AppKit's event owner without starting its run loop or showing UI.
        _ = NSApplication.shared
        let input = CommandAwareTextField()
        let text = NSTextView()
        var labels: [String] = []
        input.keyCommandHandler = { labels.append(String(describing: $0)) }
        for (selector, expected) in [(#selector(NSResponder.insertNewline(_:)), "enter"),
                                      (#selector(NSResponder.insertTab(_:)), "tab"),
                                      (#selector(NSResponder.insertBacktab(_:)), "shiftTab"),
                                      (#selector(NSResponder.cancelOperation(_:)), "escape")] {
            XCTAssertTrue(input.control(input, textView: text, doCommandBy: selector))
            XCTAssertEqual(labels.last, expected)
        }
        XCTAssertFalse(input.control(input, textView: text, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertEqual(labels.count, 4)
    }
}
