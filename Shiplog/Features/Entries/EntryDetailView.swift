import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: BuildEntry
    @State private var editing = false
    @State private var confirmsDelete = false
    @State private var error: SaveError?

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
                Label(entry.origin == .manual ? "Recorded by you" : "Imported activity", systemImage: "pencil.line")
                    .font(.caption).foregroundStyle(.secondary)
                if !entry.sources.isEmpty {
                    Eyebrow(text: "Source activity")
                    ForEach(entry.sources, id: \.identity) { source in
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
