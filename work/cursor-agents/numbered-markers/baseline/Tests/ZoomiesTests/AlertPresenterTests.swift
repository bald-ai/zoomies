import XCTest
import AppKit
@testable import Zoomies

final class AlertPresenterTests: XCTestCase {
    func testWarningActivatesAppBeforePresenting() {
        let savedActivator = AlertPresenter.appActivator
        let savedRunner = AlertPresenter.modalRunner
        defer {
            AlertPresenter.appActivator = savedActivator
            AlertPresenter.modalRunner = savedRunner
        }

        var activations = 0
        var presentedTitle: String?
        AlertPresenter.appActivator = { activations += 1 }
        AlertPresenter.modalRunner = { alert in
            presentedTitle = alert.messageText
            return .alertFirstButtonReturn
        }

        AlertPresenter.presentWarning(title: "Heads up", message: "Body")

        XCTAssertEqual(activations, 1, "Warnings must come to the front so they never hide behind other apps.")
        XCTAssertEqual(presentedTitle, "Heads up")
    }
}
