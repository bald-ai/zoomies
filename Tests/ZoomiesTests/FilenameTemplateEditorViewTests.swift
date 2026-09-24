import XCTest
import AppKit
@testable import Zoomies

final class FilenameTemplateEditorViewTests: XCTestCase {
    func testReorderRejectsInvalidPayloadAndMovesStableBlockIdentityInBothDirections() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let view = FilenameTemplateEditorView(settingsStore: store)
        let ids = store.settings.filenameTemplate.blocks.map(\.id)
        for invalid in [nil, "bad UUID", UUID().uuidString] {
            XCTAssertFalse(view.moveBlock(fromPasteboardString: invalid, toRow: 0))
            XCTAssertEqual(store.settings.filenameTemplate.blocks.map(\.id), ids)
        }
        let payload = try XCTUnwrap(view.tableView(view.tableView, pasteboardWriterForRow: 0) as? NSPasteboardItem)
        XCTAssertEqual(payload.string(forType: .init("com.zoomies.filenameTemplate.block")), ids[0].uuidString)
        XCTAssertTrue(view.moveBlock(fromPasteboardString: ids[0].uuidString, toRow: ids.count))
        XCTAssertEqual(store.settings.filenameTemplate.blocks.map(\.id), Array(ids.dropFirst()) + [ids[0]])
        XCTAssertTrue(view.moveBlock(fromPasteboardString: ids[0].uuidString, toRow: 0))
        XCTAssertEqual(store.settings.filenameTemplate.blocks.map(\.id), ids)
    }

    func testDateAndTimeControlsPersistFormatsAndResetRestoresDefaults() throws {
        _ = NSApplication.shared
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let view = FilenameTemplateEditorView(settingsStore: store)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 220)
        view.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let dateRow = try XCTUnwrap(store.settings.filenameTemplate.blocks.firstIndex { $0.kind == .date })
        let dateCell = try XCTUnwrap(view.tableView(view.tableView, viewFor: nil, row: dateRow))
        let segments = try XCTUnwrap(descendants(dateCell).compactMap { $0 as? NSSegmentedControl }.first)
        for enabled in [[true, false, false], [false, true, true], [true, true, true], [false, false, false]] {
            for index in 0..<3 { segments.setSelected(enabled[index], forSegment: index) }
            XCTAssertTrue(segments.sendAction(try XCTUnwrap(segments.action), to: segments.target))
            let expected = zip(enabled, ["yyyy", "MM", "dd"]).filter(\.0).map(\.1).joined(separator: "-")
            XCTAssertEqual(store.settings.filenameTemplate.blocks[dateRow].format, expected)
        }
        let timeRow = try XCTUnwrap(store.settings.filenameTemplate.blocks.firstIndex { $0.kind == .time })
        let timeCell = try XCTUnwrap(view.tableView(view.tableView, viewFor: nil, row: timeRow))
        let timeField = try XCTUnwrap(findEditableField(in: timeCell))
        timeField.stringValue = "HH"
        timeField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: timeField))
        XCTAssertEqual(store.settings.filenameTemplate.blocks[timeRow].format, "HH")
        let reset = try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.title == "Reset to Defaults" })
        reset.performClick(nil)
        XCTAssertEqual(store.settings.filenameTemplate.blocks.map(\.format), FilenameTemplate.defaultTemplate.blocks.map(\.format))
    }

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
