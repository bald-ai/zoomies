import XCTest
import AppKit
@testable import Zoomies

final class WorkflowPanelKeybindLabelTests: XCTestCase {
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
