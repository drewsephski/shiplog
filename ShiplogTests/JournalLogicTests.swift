import XCTest

@testable import Shiplog

final class JournalLogicTests: XCTestCase {
    private func calendar(_ zone: String = "America/Chicago") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
    private func date(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 12,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func date(_ day: Int, hour: Int = 12, calendar: Calendar) -> Date {
        date(2026, 10, day, hour: hour, calendar: calendar)
    }
    private func record(_ date: Date, projectID: UUID? = nil) -> EntryRecord {
        EntryRecord(
            id: UUID(), projectID: projectID, title: "Shipped search", detail: "", kind: .feature, occurredAt: date)
    }

    func testEmptyJournalHasNoInventedStatistics() {
        let stats = JournalLogic.stats(entries: [], activeProjectIDs: [], calendar: calendar())
        XCTAssertEqual(
            stats,
            ShippingStats(
                currentStreak: 0, longestStreak: 0, activeProjects: 0,
                entriesThisWeek: 0, shippingDaysThisWeek: 0))
    }

    func testStreakCountsDistinctDaysAndAllowsYesterday() {
        let cal = calendar()
        let entries = [record(date(3, calendar: cal)), record(date(4, calendar: cal)), record(date(4, calendar: cal))]
        let stats = JournalLogic.stats(
            entries: entries, activeProjectIDs: [], now: date(5, calendar: cal), calendar: cal)
        XCTAssertEqual(stats.currentStreak, 2)
        XCTAssertEqual(stats.longestStreak, 2)
        XCTAssertEqual(
            JournalLogic.stats(entries: entries, activeProjectIDs: [], now: date(6, calendar: cal), calendar: cal)
                .currentStreak, 0)
    }

    func testStreakAcrossSpringDSTAndYearBoundary() {
        let cal = calendar()
        let dst = [7, 8, 9].map { record(date(2026, 3, $0, calendar: cal)) }
        XCTAssertEqual(
            JournalLogic.stats(
                entries: dst, activeProjectIDs: [], now: date(2026, 3, 9, hour: 23, calendar: cal), calendar: cal
            ).currentStreak, 3)
        let year = [record(date(2025, 12, 31, calendar: cal)), record(date(2026, 1, 1, calendar: cal))]
        XCTAssertEqual(
            JournalLogic.stats(
                entries: year, activeProjectIDs: [], now: date(2026, 1, 1, hour: 23, calendar: cal), calendar: cal
            ).longestStreak, 2)
    }

    func testFutureEntriesExcludedAndArchivedProjectsNotActive() {
        let cal = calendar()
        let active = UUID()
        let archived = UUID()
        let entries = [
            record(date(5, calendar: cal), projectID: active), record(date(5, calendar: cal), projectID: archived),
            record(date(6, calendar: cal), projectID: active),
        ]
        let stats = JournalLogic.stats(
            entries: entries, activeProjectIDs: [active], now: date(5, hour: 20, calendar: cal), calendar: cal)
        XCTAssertEqual(stats.entriesThisWeek, 2)
        XCTAssertEqual(stats.shippingDaysThisWeek, 1)
        XCTAssertEqual(stats.activeProjects, 1)
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testLocalMidnightAndWeekBoundary() {
        let cal = calendar()
        let sunday = date(4, hour: 23, calendar: cal)
        let monday = date(5, hour: 1, calendar: cal)
        let records = [record(sunday), record(monday)]
        XCTAssertEqual(JournalLogic.days(for: records, calendar: cal).count, 2)
        let stats = JournalLogic.stats(entries: records, activeProjectIDs: [], now: monday, calendar: cal)
        XCTAssertEqual(stats.entriesThisWeek, 1)
        XCTAssertEqual(stats.currentStreak, 2)
    }

    func testSameInstantGroupsAccordingToUserTimeZone() {
        let utc = calendar("UTC")
        let chicago = calendar()
        let instant = date(5, hour: 1, calendar: utc)
        XCTAssertNotEqual(
            JournalLogic.reflectionKey(for: instant, calendar: utc),
            JournalLogic.reflectionKey(for: instant, calendar: chicago))
    }

    func testReflectionRetainsCivilDateAcrossTravelAndCalendarChanges() throws {
        let chicago = calendar()
        let tokyo = calendar("Asia/Tokyo")
        let key = JournalLogic.reflectionKey(for: date(4, hour: 23, calendar: chicago), calendar: chicago)
        let travelDate = try XCTUnwrap(JournalLogic.reflectionDate(for: key, calendar: tokyo))
        XCTAssertEqual(JournalLogic.reflectionKey(for: travelDate, calendar: tokyo), key)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = chicago.timeZone
        XCTAssertEqual(JournalLogic.reflectionKey(for: date(4, calendar: chicago), calendar: buddhist), key)
        XCTAssertNil(JournalLogic.reflectionDate(for: "daily:2026-99-99"))
    }

    func testTimelineSortsNewestFirstAndStableTies() {
        let cal = calendar()
        let early = record(date(4, calendar: cal))
        let late = record(date(5, calendar: cal))
        let same = record(late.occurredAt)
        let grouped = JournalLogic.days(for: [early, same, late], calendar: cal)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].entries.map(\.id), [same.id, late.id].sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(grouped[1].entries.first?.id, early.id)
    }

    func testValidationRejectsEmptyTitlesMissingProjectFutureAndUnsafeURL() throws {
        let now = Date.now
        XCTAssertThrowsError(try JournalValidation.entry(title: " \n", detail: "", projectID: UUID(), date: now))
        XCTAssertThrowsError(try JournalValidation.entry(title: "Work", detail: "", projectID: nil, date: now))
        XCTAssertThrowsError(
            try JournalValidation.entry(
                title: "Work", detail: "", projectID: UUID(), date: now.addingTimeInterval(100), now: now))
        XCTAssertThrowsError(
            try JournalValidation.project(name: "Project", overview: "", repositoryURL: "http://github.com/me/project"))
        XCTAssertThrowsError(
            try JournalValidation.project(
                name: "Project", overview: "", repositoryURL: "https://token@github.com/me/project"))
        XCTAssertThrowsError(
            try JournalValidation.project(
                name: "Project", overview: "", repositoryURL: "https://github.com/me/project?token=secret"))
        XCTAssertEqual(
            try JournalValidation.project(
                name: "Project", overview: "", repositoryURL: "  https://github.com/me/project "),
            "https://github.com/me/project")
        XCTAssertNil(try JournalValidation.project(name: "Project", overview: "", repositoryURL: ""))
    }

    func testLengthLimits() {
        XCTAssertThrowsError(
            try JournalValidation.entry(
                title: String(repeating: "a", count: 241), detail: "", projectID: UUID(), date: .now))
        XCTAssertThrowsError(
            try JournalValidation.entry(
                title: "Work", detail: String(repeating: "a", count: 20_001), projectID: UUID(), date: .now))
        XCTAssertThrowsError(
            try JournalValidation.project(name: String(repeating: "a", count: 81), overview: "", repositoryURL: ""))
    }
}
