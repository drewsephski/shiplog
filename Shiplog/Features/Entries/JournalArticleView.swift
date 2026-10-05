import SwiftUI

/// A day's narrative and work sections share the same reading layout in Today and History.
struct JournalArticleView: View {
    let entries: [BuildEntry]
    let story: JournalSummary?
    let editStory: () -> Void

    private var orderedEntries: [BuildEntry] {
        entries.sorted {
            $0.occurredAt == $1.occurredAt
                ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt < $1.occurredAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            JournalStoryView(story: story, edit: editStory)
            ForEach(orderedEntries) { entry in
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    if let project = entry.project { Eyebrow(text: project.name) }
                    Text(entry.title).font(.title2.weight(.semibold)).tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !entry.detail.isEmpty { JournalProseView(text: entry.detail) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { metadata(entry) }
                        VStack(alignment: .leading, spacing: 6) { metadata(entry) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    NavigationLink {
                        EntryDetailView(entry: entry)
                    } label: {
                        Label(
                            entry.evidenceIDs.isEmpty
                                ? "Details and edit"
                                : "\(entry.evidenceIDs.count) \(entry.evidenceIDs.count == 1 ? "source" : "sources") · Details and edit",
                            systemImage: "arrow.up.right"
                        )
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View sources and edit: \(entry.title)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func metadata(_ entry: BuildEntry) -> some View {
        Text(entry.kind.title)
        Text(entry.occurredAt, format: .dateTime.hour().minute())
        if entry.origin == .generated { Text("AI draft") }
        if entry.origin == .userEditedGenerated { Text("Edited by you") }
    }
}

struct JournalStoryView: View {
    let story: JournalSummary?
    let edit: () -> Void

    private var originLabel: String {
        switch story?.originRawValue {
        case SummaryOrigin.generatedDraft.rawValue: "AI draft · Based on your source activity"
        case SummaryOrigin.userEditedGenerated.rawValue: "Edited by you"
        default: "Written by you"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Eyebrow(
                    text: story?.originRawValue == SummaryOrigin.manual.rawValue ? "Daily reflection" : "Daily story")
                Spacer()
                Button(story == nil ? "Add" : "Edit", action: edit)
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("today.reflection")
            }
            if let story {
                JournalProseView(text: story.text)
                Text(originLabel).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("What moved forward? What did you learn?")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Plain paragraphs keep drafts readable and editable without interpreting repository markup.
struct JournalProseView: View {
    let text: String
    private var paragraphs: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(paragraphs.indices, id: \.self) { index in
                Text(paragraphs[index]).font(.body).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
