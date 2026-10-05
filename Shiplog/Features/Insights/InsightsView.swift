import SwiftData
import SwiftUI

struct InsightsView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var streakSize = 64.0
    @Query private var entries: [BuildEntry]
    @Query private var projects: [Project]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let stats = JournalLogic.stats(
                entries: entries.map(\.record),
                activeProjectIDs: Set(projects.filter { !$0.isArchived }.map(\.id)),
                now: timeline.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Keep moving forward")
                        Text("A practice,\nnot a scoreboard.").font(.largeTitle.weight(.bold)).tracking(-1)
                        Text("Meaningful work adds up. Here’s the rhythm behind yours.")
                            .foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(stats.currentStreak)").font(.system(size: streakSize, weight: .light, design: .rounded))
                            .monospacedDigit().accessibilityLabel("\(stats.currentStreak) day shipping streak")
                        Text("day shipping streak").font(.title3.weight(.medium))
                        Text(
                            stats.currentStreak == 0
                                ? "A streak starts with one logged build. Rest days are part of building, too."
                                : "At least one build each day. Your streak stays current if you shipped yesterday."
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Divider()
                    Eyebrow(text: "This week")
                    VStack(spacing: 0) {
                        metric("Build entries", value: stats.entriesThisWeek, note: "Meaningful pieces of work")
                        Divider()
                        metric("Shipping days", value: stats.shippingDaysThisWeek, note: "Days with a logged build")
                        Divider()
                        metric(
                            "Active projects", value: stats.activeProjects, note: "Unarchived projects you worked on")
                        Divider()
                        metric(
                            "Longest streak", value: stats.longestStreak, note: "Consecutive shipping days, all time")
                    }
                    Text(
                        "Based on your journal, using your local calendar. Reflections and raw commit counts don’t affect these numbers."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if entries.isEmpty {
                        Text("Log your first build on Today to begin.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
        }.navigationTitle("Insights").navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, value: Int, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium))
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(value)").font(.title2.weight(.medium)).monospacedDigit()
        }.padding(.vertical, 18).accessibilityElement(children: .combine)
    }
}
