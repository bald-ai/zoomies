import XCTest
@testable import Zoomies

final class FinderSelectionParserTests: XCTestCase {
    func testParsesNoneAndEmpty() {
        XCTAssertEqual(FinderSelectionParser.parseSelectionResult("NONE"), .none)
        XCTAssertEqual(FinderSelectionParser.parseSelectionResult("   "), .none)
    }

    func testParsesMultipleWithMinimumTwo() {
        XCTAssertEqual(FinderSelectionParser.parseSelectionResult("MULTI:7"), .multiple(count: 7))
        XCTAssertEqual(FinderSelectionParser.parseSelectionResult("MULTI:1"), .multiple(count: 2))
        XCTAssertEqual(FinderSelectionParser.parseSelectionResult("MULTI:x"), .multiple(count: 2))
    }

    func testParsesSingleWithExistingPath() {
        let result = FinderSelectionParser.parseSelectionResult("ONE:/tmp/test.png", fileExists: { $0 == "/tmp/test.png" })
        switch result {
        case .single(let url):
            XCTAssertEqual(url.path, "/tmp/test.png")
        default:
            XCTFail("Expected .single")
        }
    }

    func testParsesSingleMissingPathAsNone() {
        let result = FinderSelectionParser.parseSelectionResult("ONE:/tmp/missing.png", fileExists: { _ in false })
        XCTAssertEqual(result, .none)
    }

    func testUnexpectedValueBecomesNone() {
        XCTAssertEqual(FinderSelectionParser.parseSelectionResult("UNKNOWN"), .none)
    }

    func testSelectionReturnsFirstNonNoneResultWithoutRetry() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let file = root.appendingPathComponent("picked.png")
        try Data("x".utf8).write(to: file, options: .atomic)

        var calls = 0
        let result = try FinderSelectionService.selection { _ in
            calls += 1
            return "ONE:\(file.path)"
        }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result, .single(url: file))
    }

    func testSelectionRetriesAfterNoneAndReturnsSecondResult() throws {
        var callIndex = 0
        let result = try FinderSelectionService.selection { _ in
            callIndex += 1
            return callIndex == 1 ? "NONE" : "MULTI:3"
        }

        XCTAssertEqual(callIndex, 2)
        XCTAssertEqual(result, .multiple(count: 3))
    }

    func testSelectionReturnsNoneAfterTwoNoneResponses() throws {
        var calls = 0
        let result = try FinderSelectionService.selection { _ in
            calls += 1
            return "NONE"
        }

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result, .none)
    }

    func testSelectionPropagatesScriptError() {
        XCTAssertThrowsError(try FinderSelectionService.selection { _ in
            throw NSError(domain: "FinderSelectionServiceTests", code: -9)
        })
    }

    func testLookupTimeoutIsRetryableAndIgnoresLateSuccess() {
        var shouldHang = true
        var lateWork: (() -> Void)?
        var workerStarts = 0
        let coordinator = FinderSelectionLookupCoordinator(
            timeout: 0.01,
            executeOffMain: { work in
                workerStarts += 1
                if shouldHang {
                    lateWork = work
                } else {
                    work()
                }
            },
            scheduleTimeout: { _, work in
                if shouldHang {
                    work()
                }
            },
            deliverOnMain: { $0() }
        )

        var completions: [Result<FinderSelectionService.Selection, Error>] = []
        coordinator.requestSelection(runSelection: { .none }) { result in
            XCTAssertTrue(Thread.isMainThread)
            completions.append(result)
        }

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(workerStarts, 1)
        XCTAssertTrue(coordinator.isLookupInProgress, "Timed-out AppleScript must keep the worker gate closed")
        XCTAssertEqual(completions[0].nsError?.domain, "FinderSelectionService")
        XCTAssertEqual(completions[0].nsError?.code, -3)

        var gatedRetryStarted = false
        coordinator.requestSelection(runSelection: { .multiple(count: 2) }) { _ in
            gatedRetryStarted = true
            XCTFail("A request after the visible timeout must not start while the old worker is alive")
        }
        XCTAssertEqual(workerStarts, 1)
        XCTAssertFalse(gatedRetryStarted)

        lateWork?()
        XCTAssertEqual(completions.count, 1)
        XCTAssertFalse(coordinator.isLookupInProgress)

        shouldHang = false
        var retryCount = 0
        coordinator.requestSelection(runSelection: { .multiple(count: 2) }) { result in
            retryCount += 1
            guard case .success(.multiple(let count)) = result else {
                return XCTFail("Expected retry to succeed after the old worker returns")
            }
            XCTAssertEqual(count, 2)
        }
        XCTAssertEqual(workerStarts, 2)
        XCTAssertEqual(retryCount, 1)
    }

    func testLookupIgnoresDuplicateRequestWhilePending() {
        var started = 0
        let coordinator = FinderSelectionLookupCoordinator(
            executeOffMain: { _ in started += 1 },
            scheduleTimeout: { _, _ in },
            deliverOnMain: { $0() }
        )

        var completions = 0
        coordinator.requestSelection(runSelection: { .none }) { _ in completions += 1 }
        coordinator.requestSelection(runSelection: { .none }) { _ in
            XCTFail("Duplicate lookup should not complete")
        }

        XCTAssertEqual(started, 1)
        XCTAssertEqual(completions, 0)
        XCTAssertTrue(coordinator.isLookupInProgress)
    }

    func testLookupDeliversSuccessOnMainAndClearsInFlightState() {
        let coordinator = FinderSelectionLookupCoordinator(
            executeOffMain: { $0() },
            scheduleTimeout: { _, _ in },
            deliverOnMain: { $0() }
        )

        var delivered: FinderSelectionService.Selection?
        coordinator.requestSelection(runSelection: { .none }) { result in
            XCTAssertTrue(Thread.isMainThread)
            delivered = try? result.get()
        }

        XCTAssertEqual(delivered, FinderSelectionService.Selection.none)
        XCTAssertFalse(coordinator.isLookupInProgress)
    }

    func testLookupPreservesAutomationPermissionErrors() {
        let coordinator = FinderSelectionLookupCoordinator(
            executeOffMain: { $0() },
            scheduleTimeout: { _, _ in },
            deliverOnMain: { $0() }
        )
        let automation = NSError(
            domain: "FinderSelectionService",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "AppleEvent handler failed"]
        )

        var delivered: NSError?
        coordinator.requestSelection(runSelection: { throw automation }) { result in
            delivered = result.nsError
        }

        XCTAssertEqual(delivered?.domain, "FinderSelectionService")
        XCTAssertEqual(delivered?.code, -2)
    }
}

private extension Result where Success == FinderSelectionService.Selection, Failure == Error {
    var nsError: NSError? {
        guard case .failure(let error) = self else { return nil }
        return error as NSError
    }
}
