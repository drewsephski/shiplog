import SwiftUI

struct AppRootView: View {
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var onboardedThisSession = false

    private var needsOnboarding: Bool {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return !onboardedThisSession }
            if ProcessInfo.processInfo.arguments.contains("--preview-data") { return false }
        #endif
        return !onboardingCompleted
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "square.and.pencil") { NavigationStack { TodayView() } }
            Tab("History", systemImage: "clock") { NavigationStack { HistoryView() } }
            Tab("Projects", systemImage: "square.stack.3d.up") { NavigationStack { ProjectsView() } }
            Tab("Insights", systemImage: "chart.bar.xaxis") { NavigationStack { InsightsView() } }
        }
        .fullScreenCover(isPresented: Binding(get: { needsOnboarding }, set: { _ in })) {
            OnboardingView {
                onboardingCompleted = true
                onboardedThisSession = true
            }
            .interactiveDismissDisabled()
        }
        #if DEBUG
            .safeAreaInset(edge: .top, spacing: 0) {
                if ProcessInfo.processInfo.arguments.contains("--preview-data") {
                    Text("PREVIEW · SAMPLE JOURNAL · NOT SAVED")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(6).background(JournalDesign.surface)
                }
            }
        #endif
    }
}
