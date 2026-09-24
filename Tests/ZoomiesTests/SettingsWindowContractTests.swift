import AppKit
import Carbon
import XCTest
@testable import Zoomies

final class SettingsWindowContractTests: XCTestCase {
    private final class Fixture {
        let root: URL
        let store: SettingsStore
        let controller: SettingsWindowController
        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            controller = SettingsWindowController(settingsStore: store, hotKeyService: HotKeyService())
        }
        deinit {
            // This is an unpresented component fixture. Closing Settings in the
            // application also changes activation policy; do not invoke that.
            controller.window?.delegate = nil
            TestSupport.removeIfExists(root)
        }
        func reload() -> Settings {
            let fresh = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            fresh.load()
            return fresh.settings
        }
    }
    private func controls<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
        var found: [T] = []
        var visited = Set<ObjectIdentifier>()
        func walk(_ view: NSView) {
            guard visited.insert(ObjectIdentifier(view)).inserted else { return }
            if let match = view as? T { found.append(match) }
            for child in view.subviews { walk(child) }
            if let tabs = view as? NSTabView {
                for item in tabs.tabViewItems { if let page = item.view { walk(page) } }
            }
        }
        if let view { walk(view) }
        return found
    }
    private func invoke(_ control: NSControl) throws {
        let target = try XCTUnwrap(control.target as? NSObject)
        let action = try XCTUnwrap(control.action)
        _ = target.perform(action, with: control)
    }

    func testCaptureSizeAndRecordingRatePersistFromControlsAndReload() throws {
        let f = try Fixture()
        let popups = controls(NSPopUpButton.self, in: f.controller.window?.contentView)
        let size = try XCTUnwrap(popups.first { $0.itemTitles.contains("1920 px") })
        let rate = try XCTUnwrap(popups.first { $0.itemTitles.contains("60 FPS") })
        XCTAssertEqual(size.itemTitles, ["Original (no resize)", "800 px", "1200 px", "1600 px", "1920 px", "2400 px"])
        XCTAssertEqual(rate.itemTitles, ["30 FPS", "60 FPS", "120 FPS"])
        size.selectItem(withTitle: "1200 px")
        try invoke(size)
        rate.selectItem(withTitle: "60 FPS")
        try invoke(rate)
        XCTAssertEqual(f.reload().maxWidth, 1200)
        XCTAssertEqual(f.reload().recordingFrameRate, 60)
        XCTAssertFalse(try XCTUnwrap(f.controller.window).isVisible)
    }

    func testNotePrefixToggleAndUnicodeLimitPersistWithoutTruncatingCharacters() throws {
        let f = try Fixture()
        let buttons = controls(NSButton.self, in: f.controller.window?.contentView)
        let checkbox = try XCTUnwrap(buttons.first { $0.title == "Note prefix for screenshots" })
        let field = try XCTUnwrap(controls(NSTextField.self, in: f.controller.window?.contentView).first {
            $0.action == NSSelectorFromString("notePrefixFieldEdited:")
        })
        checkbox.state = .off
        try invoke(checkbox)
        XCTAssertFalse(field.isEnabled)
        XCTAssertFalse(f.reload().notePrefixEnabled)
        checkbox.state = .on
        try invoke(checkbox)
        XCTAssertTrue(field.isEnabled)
        let text = String(repeating: "👩‍💻", count: 51)
        field.stringValue = text
        try invoke(field)
        XCTAssertEqual(field.stringValue, String(repeating: "👩‍💻", count: 50))
        XCTAssertEqual(f.reload().notePrefix, field.stringValue)
        field.stringValue = "changed while typing"
        f.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(f.reload().notePrefix, "changed while typing")
        let unrelated = NSTextField(string: "unrelated")
        f.controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: unrelated))
        XCTAssertEqual(f.reload().notePrefix, "changed while typing")
    }

    func testDeleteConfirmationPreferenceAndShortcutsPersistIndependently() throws {
        let f = try Fixture()
        let button = try XCTUnwrap(controls(NSButton.self, in: f.controller.window?.contentView).first {
            $0.accessibilityIdentifier() == "settings.confirmBeforeClosing"
        })
        button.state = .off
        try invoke(button)
        XCTAssertFalse(f.reload().confirmBeforeClosing)
        let recorders = controls(ShortcutRecorderView.self, in: f.controller.window?.contentView)
        XCTAssertEqual(recorders.count, 5)
        XCTAssertFalse(f.controller.isRecordingAnyShortcut)
        for (index, recorder) in recorders.enumerated() {
            recorder.onChange?(.init(keyCode: UInt32(kVK_ANSI_A + index), carbonFlags: UInt32(cmdKey | optionKey | controlKey)))
        }
        let settings = f.reload()
        XCTAssertTrue(settings.shortcutsCustomized)
        let shortcuts = settings.shortcuts
        let expected = Set((0..<5).map { Shortcut(keyCode: UInt32(kVK_ANSI_A + $0), modifierFlags: UInt32(cmdKey | optionKey | controlKey)) })
        XCTAssertEqual(Set([shortcuts.screenshotArea, shortcuts.screenshotFull, shortcuts.reopenFinderSelection,
                            shortcuts.openScratchpad, shortcuts.toggleRecording]), expected)
        XCTAssertFalse(settings.confirmBeforeClosing)
        XCTAssertFalse(try XCTUnwrap(f.controller.window).isVisible)
    }
}
