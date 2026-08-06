import XCTest
import AppKit
@testable import Zoomies

final class WorkflowPanelKeybindLabelTests: XCTestCase {
    func testWorkflowPanelRestoresKeyFocusFromAnyClickWithoutActivatingApp() throws {
        let controller = RenamePanelController(initialFilename: "Screenshot.png")
        let panel = try XCTUnwrap(controller.window as? NSPanel)

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
    }

    func testSelectionOverlayUsesNonactivatingKeyPanel() {
        let panel = SelectionOverlayWindow.makeOverlayWindow(screen: nil)

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testRenamePanelShowsExpectedShortcutLabels() throws {
        let controller = RenamePanelController(initialFilename: "Screenshot_01.24.45.png")
        let labels = findLabels(in: controller.window?.contentView).map(\.stringValue)

        XCTAssertTrue(labels.contains("Filename"))
        XCTAssertTrue(labels.contains { $0.contains("⌘↩: Copy+Save") })
        XCTAssertTrue(labels.contains { $0.contains("⌘⌫: Copy+Delete") })
        XCTAssertTrue(labels.contains { $0.contains("Tab: Note") })
    }

    func testNotePanelShowsExpectedShortcutLabels() throws {
        let controller = NotePanelController(initialText: "prompt for agent")
        let labels = findLabels(in: controller.window?.contentView).map(\.stringValue)

        XCTAssertTrue(labels.contains("Note"))
        XCTAssertTrue(labels.contains { $0.contains("⌘↩: Copy+Save") })
        XCTAssertTrue(labels.contains { $0.contains("⌘⌫: Copy+Delete") })
        XCTAssertTrue(labels.contains { $0.contains("Tab: Editor") })
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
