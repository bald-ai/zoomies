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
            XCTAssertFalse(canvas.isColorPickerOpen)
        }
        store.update { $0.editorColorIDs = ["white", "purple"] }
        XCTAssertEqual(canvas.currentColor, expected[0], "Keep selected color when reordering")
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
        XCTAssertEqual(canvas.currentColor, expected[2])
        store.update { $0.editorColorIDs = ["orange"] }
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
        XCTAssertEqual(canvas.currentColor, expected[1], "Single-color palette wraps safely")
    }

    func testQAndKHaveSeparateCommandsAndModifiersDoNotCycle() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        var cycles = 0
        var pickers = 0
        canvas.onKeyCommand = { command in
            if case .cycleColor = command { cycles += 1 }
            if case .toggleColorPicker = command { pickers += 1 }
        }
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q"))
        canvas.keyDown(with: try key(kVK_ANSI_K, text: "k"))
        canvas.keyDown(with: try key(kVK_ANSI_Q, text: "q", flags: .command))
        XCTAssertEqual(cycles, 1)
        XCTAssertEqual(pickers, 1)
    }

    func testPaletteSettingsRemoveAddAndReorderAndRender() throws {
        _ = NSApplication.shared
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let view = EditorPaletteSettingsView(settingsStore: store)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 600))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        host.appearance = NSAppearance(named: .darkAqua)
        host.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20)
        ])
        try XCTUnwrap(buttons(in: view).first { $0.toolTip == "Remove Red" }).performClick(nil)
        XCTAssertEqual(store.settings.editorColorIDs.count, 5)
        try XCTUnwrap(buttons(in: view).first { $0.toolTip == "Add Purple" }).performClick(nil)
        XCTAssertEqual(store.settings.editorColorIDs.last, "purple")
        try XCTUnwrap(buttons(in: view).first { $0.toolTip == "Move Purple earlier" }).performClick(nil)
        XCTAssertEqual(store.settings.editorColorIDs[4], "purple")
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(view.frame.height, host.bounds.height - 20)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/zoomies-palette-settings.png"))
        }
    }
}
