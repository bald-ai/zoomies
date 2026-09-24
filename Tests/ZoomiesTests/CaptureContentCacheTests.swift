import XCTest
@testable import Zoomies

@MainActor
final class CaptureContentCacheTests: XCTestCase {
    func testConcurrentRequestsShareLoadAndExpiryStartsAfterCompletion() async throws {
        var now = Date(timeIntervalSince1970: 100)
        let cache = CaptureContentCache<Int>(lifetime: 2, clock: { now })
        var calls = 0
        var continuation: CheckedContinuation<Int, Never>?
        let first = cache.task {
            calls += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        let second = cache.task { calls += 1; return -1 }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        now = now.addingTimeInterval(10)
        try XCTUnwrap(continuation).resume(returning: 42)
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, 42)
        XCTAssertEqual(secondResult, 42)
        XCTAssertEqual(calls, 1)
        now = now.addingTimeInterval(1.9)
        let cached = try await cache.task { calls += 1; return -2 }.value
        XCTAssertEqual(cached, 42)
        XCTAssertEqual(calls, 1)
        now = now.addingTimeInterval(0.1)
        let refreshed = try await cache.task { calls += 1; return 43 }.value
        XCTAssertEqual(refreshed, 43)
        XCTAssertEqual(calls, 2)
    }

    func testFailedLoadIsSharedThenEvictedForRetry() async throws {
        let cache = CaptureContentCache<Int>(lifetime: 2)
        let first = cache.task { throw NSError(domain: "capture fixture", code: 17) }
        let second = cache.task { -1 }
        for request in [first, second] {
            do { _ = try await request.value; XCTFail("Expected capture failure") }
            catch { XCTAssertEqual((error as NSError).code, 17) }
        }
        let recovered = try await cache.task { 7 }.value
        XCTAssertEqual(recovered, 7)
    }
}
