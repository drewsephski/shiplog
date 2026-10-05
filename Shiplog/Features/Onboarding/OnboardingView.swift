import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(GitHubConnection.self) private var connection
    let onContinue: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ShiplogLogo(markSize: 48).padding(.top, 32)
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "For software builders")
                    Text("You’re building\nsomething.\nKeep the story.")
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Connect GitHub. Shiplog turns your work into a journal, one meaningful piece at a time.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 24) {
                    benefit(
                        "square.and.pencil", title: "Remember what moved forward",
                        detail: "Features, fixes, releases. More than a commit count.")
                    benefit(
                        "square.stack.3d.up", title: "See your projects take shape",
                        detail: "Keep the progress and the decisions together.")
                    benefit(
                        "lock", title: "Choose what Shiplog sees",
                        detail: "Select repositories, review the data transfer, and keep control of every draft.")
                }
            }.padding(.horizontal, 28).padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if connection.isBusy { ProgressView(connection.status).font(.subheadline) }
                if let error = connection.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("connection.error")
                }
                PrimaryAction(title: "Connect GitHub", symbol: "arrow.right") {
                    Task {
                        await connection.connect(context: context)
                        if connection.isConnected { onContinue() }
                    }
                }
                .disabled(connection.isBusy).accessibilityIdentifier("onboarding.github")
                Button("Keep a journal manually", action: onContinue)
                    .font(.subheadline).frame(minHeight: 44).disabled(connection.isBusy)
                    .accessibilityIdentifier("onboarding.start")
            }.padding(24).background(JournalDesign.background)
        }
    }

    private func benefit(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title3).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
