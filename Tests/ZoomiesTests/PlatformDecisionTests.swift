import AppKit
import XCTest
@testable import Zoomies

@MainActor
final class PlatformDecisionTests: XCTestCase {
    private final class TrayButton: NSButton {
        private var assignedImage: NSImage?
        override var image: NSImage? {
            get { assignedImage }
            set { assignedImage = newValue }
        }
    }

    func testFinderScriptResultsPreserveErrorsAndTrimSuccessfulOutputWithoutExecutingScript() throws {
        XCTAssertEqual(try FinderSelectionService.runAppleScriptReturningString("fixture", execute: { source in
            XCTAssertEqual(source, "fixture")
            return .init(string: "  ONE:/tmp/image.png\n", error: nil)
        }), "ONE:/tmp/image.png")
        XCTAssertEqual(try FinderSelectionService.runAppleScriptReturningString("fixture", execute: { _ in .init(string: nil, error: nil) }), "")
        XCTAssertThrowsError(try FinderSelectionService.runAppleScriptReturningString("fixture", execute: { _ in nil })) {
            XCTAssertEqual(($0 as NSError).code, -1)
            XCTAssertEqual($0.localizedDescription, "Failed to create AppleScript.")
        }
        for (dictionary, message) in [(NSDictionary(dictionary: [NSAppleScript.errorMessage: "Denied"]), "Denied"),
                                       (NSDictionary(), "Unknown AppleScript error.")] {
            XCTAssertThrowsError(try FinderSelectionService.runAppleScriptReturningString("fixture", execute: { _ in .init(string: "ignored", error: dictionary) })) {
                XCTAssertEqual(($0 as NSError).code, -2)
                XCTAssertEqual($0.localizedDescription, message)
            }
        }
    }

    func testTrayRecordingStatesAndMenuCallbacksWithoutCreatingStatusItem() throws {
        _ = NSApplication.shared
        let button = TrayButton()
        var settings = 0
        var quits = 0
        let tray = TrayService(button: button, onShowSettings: { settings += 1 }, onQuit: { quits += 1 })
        XCTAssertNotNil(button.image)
        tray.updateRecording(state: .starting, elapsed: 99)
        XCTAssertEqual(button.attributedTitle.string, "0")
        XCTAssertNil(button.image)
        tray.updateRecording(state: .recording, elapsed: 12.9)
        XCTAssertEqual(button.attributedTitle.string, "12")
        tray.updateRecording(state: .stopping, elapsed: 100)
        XCTAssertEqual(button.attributedTitle.string, "60")
        tray.updateRecording(state: .recording, elapsed: -2)
        XCTAssertEqual(button.attributedTitle.string, "0")
        tray.updateRecording(state: .idle, elapsed: 0)
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertNotNil(button.image)
        let menu = try XCTUnwrap(tray.menu)
        XCTAssertEqual(menu.items.map(\.title), ["Settings", "", "Quit"])
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 2)
        XCTAssertEqual(settings, 1)
        XCTAssertEqual(quits, 1)
        let absent = TrayService(button: nil, onShowSettings: {})
        absent.updateRecording(state: .idle, elapsed: 0)
        XCTAssertEqual(absent.menu.items.count, 3)
    }

    func testSettingsWarningOpensRequestedURLOnlyForFirstButtonWithoutActivatingOrPresenting() {
        _ = NSApplication.shared
        let activate = AlertPresenter.appActivator
        let modal = AlertPresenter.modalRunner
        let open = AlertPresenter.urlOpener
        defer { AlertPresenter.appActivator = activate; AlertPresenter.modalRunner = modal; AlertPresenter.urlOpener = open }
        var urls: [URL] = []
        var response = NSApplication.ModalResponse.alertFirstButtonReturn
        var titles: [String] = []
        AlertPresenter.appActivator = {}
        AlertPresenter.modalRunner = { alert in
            titles.append(alert.messageText)
            XCTAssertEqual(alert.informativeText, "message")
            XCTAssertEqual(alert.buttons.map(\.title), ["Open System Settings", "OK"])
            return response
        }
        AlertPresenter.urlOpener = { urls.append($0) }
        AlertPresenter.presentWarningWithSettingsButton(title: "warning", message: "message", settingsURL: "fixture://settings")
        XCTAssertEqual(urls.map(\.absoluteString), ["fixture://settings"])
        response = .alertSecondButtonReturn
        AlertPresenter.presentWarningWithSettingsButton(title: "second", message: "message", settingsURL: "fixture://ignored")
        XCTAssertEqual(titles, ["warning", "second"])
        XCTAssertEqual(urls.count, 1)
    }
}
