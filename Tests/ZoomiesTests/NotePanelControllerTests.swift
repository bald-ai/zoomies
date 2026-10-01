import XCTest
import AppKit
@testable import Zoomies

final class NotePanelControllerTests: XCTestCase {
    func testNotePanelLocksEditorTextToWhite() throws {
        let controller = NotePanelController(initialText: "hello")
        let textView = try XCTUnwrap(findTextView(in: controller.window?.contentView))

        XCTAssertEqual(textView.textColor, .white)
        XCTAssertEqual(textView.insertionPointColor, .white)
        XCTAssertEqual(textView.typingAttributes[.foregroundColor] as? NSColor, .white)

        textView.typingAttributes[.foregroundColor] = NSColor.black
        let coloredText = NSAttributedString(string: " pasted", attributes: [.foregroundColor: NSColor.black])
        textView.insertText(coloredText, replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(textView.string, "hello pasted")

        XCTAssertEqual(textView.textColor, .white)
        XCTAssertEqual(textView.insertionPointColor, .white)
        XCTAssertEqual(textView.typingAttributes[.foregroundColor] as? NSColor, .white)

        let effectiveColor = textView.textStorage?.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        XCTAssertEqual(effectiveColor, .white)
    }

    func testShortcutLabelAdvertisesSave() throws {
        let controller = NotePanelController(initialText: "")
        let labels = findLabels(in: controller.window?.contentView).map(\.stringValue)

        XCTAssertTrue(labels.contains { $0.contains("Enter: Save") })
    }

    func testStandaloneNoteSavesFullGenerousLimit() throws {
        let content = String(repeating: "a", count: 99_999) + "🌻"
        let controller = NotePanelController(initialText: content, maxLength: NotePanelController.standaloneMaxLength)
        let textView = try XCTUnwrap(findTextView(in: controller.window?.contentView))
        XCTAssertEqual(controller.text, content)
        var saved: String?
        controller.onAction = { if case .save(let text) = $0 { saved = text } }
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        textView.keyDown(with: enter)
        XCTAssertEqual(saved, content)
    }

    func testOversizedPasteIsRejectedWithoutChangingExistingText() throws {
        let controller = NotePanelController(initialText: "keep this", maxLength: NotePanelController.standaloneMaxLength)
        let textView = try XCTUnwrap(findTextView(in: controller.window?.contentView))
        XCTAssertFalse(textView.shouldChangeText(in: NSRange(location: 0, length: 9), replacementString: String(repeating: "x", count: 100_001)))
        XCTAssertEqual(controller.text, "keep this")
        XCTAssertTrue(findLabels(in: controller.window?.contentView).contains { !$0.isHidden && $0.stringValue.contains("character limit") })
    }

    func testBoundaryAllowsReplacementAndDeletionAndImageLimitStays1000() throws {
        for limit in [1000, NotePanelController.standaloneMaxLength] {
            let controller = NotePanelController(initialText: String(repeating: "a", count: limit), maxLength: limit)
            let textView = try XCTUnwrap(findTextView(in: controller.window?.contentView))
            XCTAssertFalse(textView.shouldChangeText(in: NSRange(location: limit, length: 0), replacementString: "b"))
            XCTAssertTrue(textView.shouldChangeText(in: NSRange(location: limit - 1, length: 1), replacementString: "🌻"))
            XCTAssertTrue(textView.shouldChangeText(in: NSRange(location: limit - 1, length: 1), replacementString: ""))
        }
        let imageNote = NotePanelController(initialText: String(repeating: "x", count: 1100))
        XCTAssertEqual(imageNote.text.count, 1000)
    }

    func testScreenshotPanelAppliesItsOwnLayoutAndLimit() throws {
        let screenshot = ScreenshotNotePanelController(initialText: String(repeating: "s", count: WorkflowNoteRenderer.maxNoteLength + 350))
        XCTAssertEqual(screenshot.text.count, WorkflowNoteRenderer.maxNoteLength)
        let layout = ScreenshotNotePanelController.layout
        let textView = try XCTUnwrap(findTextView(in: screenshot.window?.contentView))
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        XCTAssertEqual(scrollView.hasVerticalScroller, layout.hasVerticalScroller)
        XCTAssertEqual(scrollView.autohidesScrollers, layout.autohidesScrollers)
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func findLabels(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        var result: [NSTextField] = []
        if let label = view as? NSTextField {
            result.append(label)
        }
        for subview in view.subviews {
            result.append(contentsOf: findLabels(in: subview))
        }
        return result
    }
}
