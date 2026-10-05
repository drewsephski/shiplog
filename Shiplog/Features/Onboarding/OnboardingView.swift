import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 12) {
                    ShiplogMark()
                    Text("Shiplog").font(.title3.weight(.semibold))
                }.padding(.top, 32)
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: "For software builders")
                    Text("You’re building\nsomething.\nKeep the story.")
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A personal journal of what you ship, one meaningful piece of work at a time.")
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
                        "lock", title: "Start with your own words",
                        detail: "Your journal stays on this iPhone. GitHub connection is coming later.")
                }
            }.padding(.horizontal, 28).padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryAction(title: "Start my journal", symbol: "arrow.right", action: onContinue)
                    .accessibilityIdentifier("onboarding.start")
                Text("No account needed.").font(.caption).foregroundStyle(.secondary)
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
