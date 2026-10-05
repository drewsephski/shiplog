import Foundation

/// Poll a pending draft promptly, but let a loaded journal remain a quiet read.
struct JournalRefreshPolicy {
    private var day: AgentDay?
    private var lastAttempt: Date?
    private var jobStatus = "idle"

    func shouldRefresh(day: AgentDay, at now: Date) -> Bool {
        guard let previous = self.day, let lastAttempt,
            previous.day == day.day, previous.timeZone == day.timeZone
        else { return true }
        let interval: TimeInterval = ["pending", "running"].contains(jobStatus) ? 30 : 300
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    mutating func recordAttempt(day: AgentDay, at now: Date) {
        self.day = day
        lastAttempt = now
    }

    mutating func recordResult(status: String, day: AgentDay, at now: Date) {
        recordAttempt(day: day, at: now)
        jobStatus = status
    }
}
