import Foundation

struct EntryRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let projectID: UUID?
    let title: String
    let detail: String
    let kind: BuildKind
    let occurredAt: Date
}

struct JournalDay: Identifiable, Sendable {
    let date: Date
    let entries: [EntryRecord]
    var id: Date { date }
}

struct ShippingStats: Equatable, Sendable {
    let currentStreak: Int
    let longestStreak: Int
    let activeProjects: Int
    let entriesThisWeek: Int
    let shippingDaysThisWeek: Int
}

enum JournalLogic {
    static func days(for entries: [EntryRecord], calendar: Calendar = .current) -> [JournalDay] {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.occurredAt) }
            .map {
                JournalDay(
                    date: $0.key,
                    entries: $0.value.sorted {
                        if $0.occurredAt == $1.occurredAt { return $0.id.uuidString < $1.id.uuidString }
                        return $0.occurredAt > $1.occurredAt
                    })
            }
            .sorted { $0.date > $1.date }
    }

    /// A streak stays current through today when yesterday was a shipping day.
    /// Calendar arithmetic handles DST, time zones, and year boundaries.
    static func stats(
        entries: [EntryRecord], activeProjectIDs: Set<UUID>,
        now: Date = .now, calendar: Calendar = .current
    ) -> ShippingStats {
        let eligible = entries.filter { $0.occurredAt <= now }
        let days = Set(eligible.map { calendar.startOfDay(for: $0.occurredAt) })
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = days.contains(today) ? today : yesterday
        var current = 0
        while days.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            run = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let recent = eligible.filter { entry in
            guard let week else { return false }
            return entry.occurredAt >= week.start && entry.occurredAt < week.end
        }
        let recentIDs = Set(recent.compactMap(\.projectID))
        return ShippingStats(
            currentStreak: current, longestStreak: longest,
            activeProjects: recentIDs.intersection(activeProjectIDs).count,
            entriesThisWeek: recent.count,
            shippingDaysThisWeek: Set(recent.map { calendar.startOfDay(for: $0.occurredAt) }).count)
    }

    static func reflectionKey(for date: Date, calendar: Calendar = .current) -> String {
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        let parts = civilCalendar.dateComponents([.year, .month, .day], from: date)
        return "daily:\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Reflections stay on the civil date they were written for, including after travel.
    static func reflectionDate(for key: String, calendar: Calendar = .current) -> Date? {
        guard key.hasPrefix("daily:") else { return nil }
        let values = key.dropFirst(6).split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        let components = DateComponents(year: values[0], month: values[1], day: values[2])
        guard let date = civilCalendar.date(from: components), reflectionKey(for: date, calendar: calendar) == key
        else {
            return nil
        }
        return date
    }

}

extension BuildEntry {
    var record: EntryRecord {
        EntryRecord(
            id: id, projectID: project?.id, title: title, detail: detail,
            kind: kind, occurredAt: occurredAt)
    }
}
