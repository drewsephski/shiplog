#if DEBUG
    import SwiftUI
    import SwiftData

    /// These fictional examples never enter the on-device production store.
    @MainActor enum PreviewFixtures {
        static func container(populated: Bool = true) throws -> ModelContainer {
            let container = try Persistence.container(inMemory: true)
            if populated { try populate(container.mainContext) }
            container.mainContext.autosaveEnabled = false
            return container
        }

        static func populate(_ context: ModelContext) throws {
            let project = Project(
                name: "Fieldnotes", overview: "A quieter place to collect ideas.",
                createdAt: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now)
            let second = Project(name: "Wayfinder", overview: "A small walking route planner.")
            context.insert(project)
            context.insert(second)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let firstTime = min(calendar.date(byAdding: .hour, value: 9, to: today) ?? today, .now)
            let secondTime = min(calendar.date(byAdding: .hour, value: 11, to: today) ?? today, .now)
            context.insert(
                BuildEntry(
                    title: "Made search feel instant",
                    detail:
                        "Added local indexing and keyboard shortcuts. Finding an old idea now takes a moment, not a scroll.",
                    kind: .improvement, occurredAt: firstTime, project: project))
            context.insert(
                BuildEntry(
                    title: "Shipped the first saved routes",
                    detail:
                        "Routes can be named, saved, and picked up again. The first complete loop from discovery to a walk.",
                    kind: .feature, occurredAt: secondTime, project: second))
            for offset in [1, 2, 4, 6] {
                let date = calendar.date(byAdding: .day, value: -offset, to: firstTime) ?? today
                let titles = [
                    1: "Kept drafts safe between launches", 2: "Released the first private beta",
                    4: "Simplified the note editor", 6: "Built the first capture flow",
                ]
                context.insert(
                    BuildEntry(
                        title: titles[offset] ?? "Improved the editor", kind: offset == 2 ? .release : .feature,
                        occurredAt: date, project: project))
            }
            try JournalStore.saveReflection(
                context: context, date: .now,
                text:
                    "Two small pieces clicked into place. The best progress today was making the existing things easier to use."
            )
            try context.save()
        }
    }

    #Preview("Today · sample journal") {
        if let container = try? PreviewFixtures.container() {
            NavigationStack { TodayView() }.modelContainer(container).environment(GitHubConnection()).preferredColorScheme(.dark)
        }
    }

    #Preview("Today · first use") {
        if let container = try? PreviewFixtures.container(populated: false) {
            NavigationStack { TodayView() }.modelContainer(container).environment(GitHubConnection())
        }
    }

    #Preview("Onboarding") { OnboardingView {}.environment(GitHubConnection()).preferredColorScheme(.dark) }

    #Preview("Projects · sample journal") {
        if let container = try? PreviewFixtures.container() {
            NavigationStack { ProjectsView() }.modelContainer(container)
        }
    }

    #Preview("Insights · sample journal") {
        if let container = try? PreviewFixtures.container() {
            NavigationStack { InsightsView() }.modelContainer(container).preferredColorScheme(.dark)
        }
    }
#endif
