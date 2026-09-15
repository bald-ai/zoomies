import XCTest
import AppKit
@testable import Zoomies

final class FilenameTemplateEditorViewTests: XCTestCase {
    func testTextKeystrokeDoesNotRebuildCells() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        settingsStore.load()

        let view = FilenameTemplateEditorView(settingsStore: settingsStore)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        view.layoutSubtreeIfNeeded()

        // Row 0 of the default template is the static-text block, editable.
        let before = try XCTUnwrap(view.tableView.rowView(atRow: 0, makeIfNecessary: false))
        let field = try XCTUnwrap(findEditableField(in: before))

        field.stringValue = "ShotX"
        // Drive the real keystroke path: the cell is the field's delegate and
        // forwards to the view's reload-free update.
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))

        XCTAssertEqual(settingsStore.settings.filenameTemplate.blocks[0].text, "ShotX")
        XCTAssertTrue(
            view.tableView.rowView(atRow: 0, makeIfNecessary: false) === before,
            "Typing must not reload the table, or the field loses focus after every keystroke."
        )
    }

    private func findEditableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let field = findEditableField(in: subview) {
                return field
            }
        }
        return nil
    }
}
