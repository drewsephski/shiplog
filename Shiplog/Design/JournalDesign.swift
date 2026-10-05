import SwiftUI

// Semantic colors adapt to system appearance and increased contrast.
enum JournalDesign {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let hairline = Color.primary.opacity(0.12)
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}

struct JournalEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            Text(message).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

struct PrimaryAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
        .foregroundStyle(JournalDesign.background)
        .controlSize(.large)
    }
}

struct SaveError: Identifiable {
    let id = UUID()
    let message: String
    init(_ error: Error) {
        if let validation = error as? JournalValidationError {
            message = validation.localizedDescription
        } else {
            message = "Your changes couldn’t be saved. Please try again. Your existing journal is still here."
        }
    }
}

extension View {
    func journalError(_ error: Binding<SaveError?>) -> some View {
        alert(
            "Couldn’t save",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue?.message ?? "Please try again.")
        }
    }
}

struct EntryRow: View {
    let entry: BuildEntry
    var showsProject = true
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: entry.kind.symbol)
                .font(.body.weight(.medium))
                .frame(width: 32, height: 36)
                .background(JournalDesign.surface, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                if showsProject {
                    Text(entry.project?.name ?? "Unassigned project")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Text(entry.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.detail.isEmpty {
                    Text(entry.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(entry.kind.title)
                    Text("·")
                    Text(entry.occurredAt, format: .dateTime.hour().minute())
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
