import AppKit
import Carbon
import XCTest
@testable import Zoomies

final class SettingsWindowContractTests: XCTestCase {
    private final class Fixture {
        let root: URL
        let store: SettingsStore
        let controller: SettingsWindowController
        var blocker: String?
        var confirmAnswer = true
        var asked: [String] = []
        var askedOn: [NSWindow?] = []
        var relaunches = 0
        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            var restart = SettingsWindowController.Restart()
            var box: Fixture?
            restart.blocker = { box?.blocker }
            restart.ask = { alert, window, done in
                box?.asked.append(alert.messageText)
                box?.askedOn.append(window)
                done(box?.confirmAnswer == true ? .alertFirstButtonReturn : .alertSecondButtonReturn)
            }
            restart.relaunch = { box?.relaunches += 1 }
            controller = SettingsWindowController(settingsStore: store, hotKeyService: HotKeyService(), restart: restart)
            box = self
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

    func testEverySettingIsOnOnePageAndCommandWCloses() throws {
        let f = try Fixture()
        let window = try XCTUnwrap(f.controller.window as? SettingsWindow)
        XCTAssertTrue(controls(NSTabView.self, in: window.contentView).isEmpty)
        XCTAssertTrue(controls(NSSegmentedControl.self, in: window.contentView).isEmpty)
        XCTAssertNotNil(controls(EditorPaletteSettingsView.self, in: window.contentView).first)
        XCTAssertEqual(controls(ShortcutRecorderView.self, in: window.contentView).count, 5)
        let commandW = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        XCTAssertTrue(window.performKeyEquivalent(with: commandW))
        XCTAssertFalse(window.isVisible)
    }

    func testExperimentalToggleSavesOnlyWhenItRestarts() throws {
        let f = try Fixture()
        let toggle = try XCTUnwrap(controls(NSButton.self, in: f.controller.window?.contentView).first {
            $0.accessibilityIdentifier() == "settings.experimentalNoteEditor"
        })
        XCTAssertEqual(toggle.state, .off)

        f.blocker = "Save or close the open note first, then try again."
        toggle.state = .on
        try invoke(toggle)
        XCTAssertEqual(f.asked, ["Zoomies can't restart right now"], "Open work blocks the restart")
        XCTAssertEqual(toggle.state, .off)
        XCTAssertEqual(f.relaunches, 0)
        XCTAssertFalse(f.store.settings.experimentalNoteEditor)

        f.blocker = nil
        f.confirmAnswer = false
        toggle.state = .on
        try invoke(toggle)
        XCTAssertEqual(f.asked.last, "Turn on the drawing editor?")
        XCTAssertTrue(f.askedOn.allSatisfy { $0 === f.controller.window }, "Shown on Settings, so it follows it to full screen")
        XCTAssertEqual(toggle.state, .off, "Cancel leaves it as it was")
        XCTAssertFalse(f.reload().experimentalNoteEditor)
        XCTAssertEqual(f.relaunches, 0)

        f.confirmAnswer = true
        toggle.state = .on
        try invoke(toggle)
        XCTAssertEqual(toggle.state, .on)
        XCTAssertTrue(f.reload().experimentalNoteEditor)
        XCTAssertEqual(f.relaunches, 1)
    }
}
