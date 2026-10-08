import AppKit
import Carbon
import XCTest
@testable import Zoomies

final class EditorPaletteTests: XCTestCase {
    private func key(_ code: Int, text: String, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: UInt16(code)))
    }
    private func canvas(in view: NSView?) -> EditorCanvasView? {
        if let canvas = view as? EditorCanvasView { return canvas }
        return view?.subviews.compactMap { canvas(in: $0) }.first
    }
    private func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    func testLegacySettingsKeepOriginalPaletteAndNormalizationPreservesOrder() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.editorColorIDs, ["red", "blue", "green", "black", "yellow", "white"])
        XCTAssertEqual(EditorPalette.normalized(["purple", "unknown", "purple", "orange"]), ["purple", "orange"])
        XCTAssertEqual(EditorPalette.normalized([]), EditorPalette.defaultIDs)
        XCTAssertEqual(EditorPalette.normalized(EditorPalette.available.map(\.id)).count, 6)
        XCTAssertEqual(EditorPalette.normalized(["teal"]), ["teal"])
    }

    func testOrderedPalettePersistsAndReportsInvalidRepair() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let url = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)
        store.update { $0.editorColorIDs = ["cyan", "black", "pink"] }
        let restored = SettingsStore(fileURL: url)
        restored.load()
        XCTAssertEqual(restored.settings.editorColorIDs, ["cyan", "black", "pink"])
        var invalid = Settings.default
        invalid.editorColorIDs = ["bad", "orange", "orange"]
        let result = invalid.normalizedReportingRepairs()
        XCTAssertTrue(result.repairedInvalidFields)
        XCTAssertEqual(result.settings.editorColorIDs, ["orange"])
    }

    func testQCyclesCustomOrderWrapsAndRespondsToLiveSettings() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        store.update { $0.editorColorIDs = ["purple", "orange", "white"] }
        let controller = EditorWindowController(image: TestSupport.solidImage(width: 200, height: 100), settingsStore: store)
        defer { controller.dismissWithoutCompletion() }
        let canvas = try XCTUnwrap(canvas(in: controller.window?.contentView))
        let expected = EditorPalette.colors(for: store.settings.editorColorIDs).map(\.color)
        XCTAssertEqual(canvas.currentColor, expected[0])
        for index in [1, 2, 0] {
            canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
            XCTAssertEqual(canvas.currentColor, expected[index])
        }
        store.update { $0.editorColorIDs = ["white", "purple"] }
        XCTAssertEqual(canvas.currentColor, expected[0], "Keep selected color when reordering")
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
        XCTAssertEqual(canvas.currentColor, expected[2])
        store.update { $0.editorColorIDs = ["orange"] }
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
        XCTAssertEqual(canvas.currentColor, expected[1], "Single-color palette wraps safely")
    }

    func testOnlyUnmodifiedQCyclesColor() throws {
        let canvas = TestSupport.swallowingUnhandledKeys(EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80)))
        var cycles = 0
        canvas.onKeyCommand = { command in
            if case .cycleColor = command { cycles += 1 }
        }
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
        canvas.keyDown(with: try key(kVK_ANSI_K, text: "k"))
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q", flags: .command))
        XCTAssertEqual(cycles, 1)
    }

    func testClickingColorSwatchCyclesColor() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let controller = EditorWindowController(image: TestSupport.solidImage(width: 200, height: 100), settingsStore: store)
        defer { controller.dismissWithoutCompletion() }
        let canvas = try XCTUnwrap(canvas(in: controller.window?.contentView))
        let swatch = try XCTUnwrap(buttons(in: controller.window?.contentView).first { $0.toolTip == "Next color (Q)" })
        let expected = EditorPalette.colors(for: store.settings.editorColorIDs).map(\.color)
        swatch.performClick(nil)
        XCTAssertEqual(canvas.currentColor, expected[1])
    }

    private func buttons(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        let own = (view as? NSButton).map { [$0] } ?? []
        return own + view.subviews.flatMap { buttons(in: $0) }
    }

    func testPaletteSettingsRemoveAddAndReorderInOneCompactRow() throws {
        _ = NSApplication.shared
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let view = EditorPaletteSettingsView(settingsStore: store)
        func perform(_ menu: NSMenu, _ title: String) throws {
            let item = try XCTUnwrap(menu.items.first { $0.title == title })
            XCTAssertTrue(item.isEnabled, title)
            menu.performActionForItem(at: menu.index(of: item))
        }

        try perform(view.menu(forColorAt: 0), "Remove Red")
        XCTAssertEqual(store.settings.editorColorIDs.count, 5)
        XCTAssertEqual(view.menu(forColorAt: 0).items.map(\.title), ["Remove Blue"])

        let add = view.addMenu()
        XCTAssertEqual(add.items.count, EditorPalette.available.count)
        XCTAssertEqual(add.items.first { $0.title == "Blue" }?.state, .on)
        try perform(add, "Purple")
        XCTAssertEqual(store.settings.editorColorIDs.last, "purple")
        XCTAssertEqual(view.strip.colors.last?.id, "purple")
        // Full palette: inactive colors can't be added, active ones can be removed.
        XCTAssertFalse(try XCTUnwrap(view.addMenu().items.first { $0.title == "Orange" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(view.addMenu().items.first { $0.title == "Purple" }).isEnabled)

        view.strip.onMove?(5, 0)
        XCTAssertEqual(store.settings.editorColorIDs.first, "purple")

        // Six colors still fit on one row.
        XCTAssertLessThanOrEqual(view.strip.intrinsicContentSize.width, 240)
        XCTAssertLessThanOrEqual(view.fittingSize.height, 120)
    }
}
