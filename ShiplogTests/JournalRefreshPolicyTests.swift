import XCTest

@testable import Shiplog

final class JournalRefreshPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_223_200)
    private var day: AgentDay { AgentDay(date: start, timeZone: TimeZone(identifier: "America/Chicago")!) }

    func testLoadedJournalDoesNotRefreshOnEveryMinuteOrViewAppearance() {
        var policy = JournalRefreshPolicy()
        XCTAssertTrue(policy.shouldRefresh(day: day, at: start))
        policy.recordResult(status: "completed", day: day, at: start)
        for seconds in [0.0, 30, 60, 120, 299] {
            XCTAssertFalse(policy.shouldRefresh(day: day, at: start.addingTimeInterval(seconds)))
        }
        XCTAssertTrue(policy.shouldRefresh(day: day, at: start.addingTimeInterval(300)))
    }

    func testPollingStopsWhenPendingGenerationCompletes() {
        var policy = JournalRefreshPolicy()
        policy.recordResult(status: "pending", day: day, at: start)
        XCTAssertFalse(policy.shouldRefresh(day: day, at: start.addingTimeInterval(29)))
        XCTAssertTrue(policy.shouldRefresh(day: day, at: start.addingTimeInterval(30)))
        let completed = start.addingTimeInterval(30)
        policy.recordResult(status: "completed", day: day, at: completed)
        XCTAssertFalse(policy.shouldRefresh(day: day, at: completed.addingTimeInterval(60)))
        XCTAssertTrue(policy.shouldRefresh(day: day, at: completed.addingTimeInterval(300)))
    }

    func testDayAndTimeZoneChangesBypassCooldown() {
        var policy = JournalRefreshPolicy()
        policy.recordResult(status: "completed", day: day, at: start)
        let tomorrow = AgentDay(
            date: start.addingTimeInterval(86_400), timeZone: TimeZone(identifier: "America/Chicago")!)
        let traveled = AgentDay(date: start, timeZone: TimeZone(identifier: "Europe/London")!)
        XCTAssertTrue(policy.shouldRefresh(day: tomorrow, at: start))
        XCTAssertTrue(policy.shouldRefresh(day: traveled, at: start))
    }

    func testFailedAttemptsHaveACooldown() {
        var policy = JournalRefreshPolicy()
        policy.recordAttempt(day: day, at: start)
        XCTAssertFalse(policy.shouldRefresh(day: day, at: start.addingTimeInterval(60)))
        XCTAssertTrue(policy.shouldRefresh(day: day, at: start.addingTimeInterval(300)))
    }
}
