import XCTest
@testable import BachDichCore

final class TranslationPolicyTests: XCTestCase {
    func testLatestOnlyAndNoConcurrentRequests() {
        var policy = TranslationPolicy(interval: 3, limit: 10)
        policy.offer("old"); policy.offer("new")
        XCTAssertEqual(policy.take(now: 100), "new")
        policy.offer("newer")
        XCTAssertNil(policy.take(now: 104))
        policy.complete(text: "new", success: true, now: 104)
        XCTAssertEqual(policy.take(now: 104), "newer")
    }
    func testThrottleAndDuplicateSubtitles() {
        var policy = TranslationPolicy(interval: 3, limit: 10)
        policy.offer("hello")
        XCTAssertEqual(policy.take(now: 100), "hello")
        policy.complete(text: "hello", success: true, now: 101)
        policy.offer("hello\n ")
        XCTAssertNil(policy.take(now: 104))
        policy.offer("world")
        XCTAssertNil(policy.take(now: 102))
        XCTAssertEqual(policy.take(now: 103), "world")
    }
    func testQuotaCountsFailedRequestsAndNeverExceedsLimit() {
        var policy = TranslationPolicy(interval: 2, limit: 1)
        policy.offer("hello")
        XCTAssertNotNil(policy.take(now: 100))
        policy.complete(text: "hello", success: false, now: 100)
        XCTAssertTrue(policy.reachedLimit)
        XCTAssertNil(policy.take(now: 200))
        XCTAssertEqual(policy.requests, 1)
    }
    func testRateLimitBackoffKeepsNewestCaption() {
        var policy = TranslationPolicy(interval: 3, limit: 10)
        policy.offer("first"); _ = policy.take(now: 100)
        policy.offer("second")
        policy.complete(text: "first", success: false, now: 101, retryAfter: 30)
        XCTAssertNil(policy.take(now: 130))
        XCTAssertEqual(policy.take(now: 131), "second")
    }
    func testPauseClearsPendingAndBoundsText() {
        var policy = TranslationPolicy(interval: 3, limit: 10)
        policy.offer(String(repeating: "中", count: 2000))
        XCTAssertEqual(policy.pending.count, 900)
        policy.discardPending()
        XCTAssertNil(policy.take(now: 100))
    }
    func testSessionFilesDoNotContainAPIKey() throws {
        let settings = String(decoding: try JSONEncoder().encode(AppSettings()), as: UTF8.self)
        let snapshot = String(decoding: try JSONEncoder().encode(CaptureSnapshot()), as: UTF8.self)
        XCTAssertFalse(settings.contains("apiKey"))
        XCTAssertFalse(snapshot.contains("apiKey"))
        XCTAssertFalse(AppSettings().cloudConsent)
    }
}
