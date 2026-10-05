import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: BuildEntry
    @Query private var remoteSources: [SourceActivity]
    @State private var editing = false
    @State private var confirmsDelete = false
    @State private var error: SaveError?

    init(entry: BuildEntry) {
        self.entry = entry
        let ids = entry.evidenceIDs
        _remoteSources = Query(
            filter: #Predicate<SourceActivity> { ids.contains($0.identity) }, sort: \SourceActivity.occurredAt)
    }
    private var sources: [SourceActivity] {
        (entry.sources + remoteSources).reduce(into: [String: SourceActivity]()) { $0[$1.identity] = $1 }.values.sorted
        { $0.occurredAt < $1.occurredAt }
    }
    private var originLabel: String {
        switch entry.origin {
        case .manual: "Recorded by you"
        case .imported: "Imported activity"
        case .generated: "AI draft · Based on source activity"
        case .userEditedGenerated: "Edited by you · AI draft preserved"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(entry.kind.title, systemImage: entry.kind.symbol)
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(entry.title).font(.largeTitle.weight(.bold)).tracking(-0.7)
                if let project = entry.project {
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        Label(project.name, systemImage: "square.stack.3d.up")
                    }.font(.subheadline.weight(.medium))
                }
                Text(entry.occurredAt, format: .dateTime.month(.wide).day().year().hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
                Divider()
                if !entry.detail.isEmpty { Text(entry.detail).font(.body).textSelection(.enabled) }
                Label(originLabel, systemImage: "pencil.line")
                    .font(.caption).foregroundStyle(.secondary)
                if let confidence = entry.confidence {
                    Text("Model confidence: \(Int(confidence * 100))% · Review against the sources.").font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !sources.isEmpty {
                    Eyebrow(text: "Source activity")
                    ForEach(sources, id: \.identity) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source.title).font(.subheadline)
                            Text(source.provider).font(.caption).foregroundStyle(.secondary)
                            if let value = source.url, let url = URL(string: value), url.scheme == "https" {
                                Link("View source", destination: url).font(.subheadline)
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .navigationTitle("Build entry").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Edit entry", systemImage: "pencil") { editing = true }
                Button("Delete entry", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }.accessibilityLabel("Entry actions")
        }
        .sheet(isPresented: $editing) { EntryEditorView(existing: entry) }
        .confirmationDialog("Delete this build entry?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                do {
                    try JournalStore.delete(entry, context: context)
                    dismiss()
                } catch { self.error = SaveError(error) }
            }
        } message: {
            Text("This removes the entry and its source links from your journal.")
        }
        .journalError($error)
    }
}
