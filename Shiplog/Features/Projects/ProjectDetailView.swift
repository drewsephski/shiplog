import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var sheet: Sheet?
    @State private var confirmsDelete = false
    @State private var error: SaveError?
    private enum Sheet: String, Identifiable {
        case edit, entry
        var id: String { rawValue }
    }
    private var days: [JournalDay] { JournalLogic.days(for: project.entries.map(\.record)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(
                    project.isArchived ? "Archived project" : "Project",
                    systemImage: project.isArchived ? "archivebox" : "square.stack.3d.up"
                )
                .font(.subheadline).foregroundStyle(.secondary)
                Text(project.name).font(.largeTitle.weight(.bold)).tracking(-0.7)
                if !project.overview.isEmpty {
                    Text(project.overview).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let value = project.repositoryURL, let url = URL(string: value), url.scheme == "https" {
                    Link(destination: url) { Label("Repository", systemImage: "arrow.up.right") }.font(.subheadline)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 28) { projectMetrics }
                    VStack(alignment: .leading, spacing: 16) { projectMetrics }
                }
                Divider()
                HStack {
                    Eyebrow(text: "The build story")
                    Spacer()
                    if !project.isArchived {
                        Button {
                            sheet = .entry
                        } label: {
                            Image(systemName: "plus")
                        }
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Log a build for this project")
                    }
                }
                if project.entries.isEmpty {
                    JournalEmptyState(
                        symbol: "text.alignleft", title: "The first chapter is yours.",
                        message: "Log the first meaningful piece of work to start this project’s story.")
                    if !project.isArchived { PrimaryAction(title: "Log a build", symbol: "plus") { sheet = .entry } }
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Eyebrow(text: day.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                ForEach(day.entries) { record in
                                    if let entry = project.entries.first(where: { $0.id == record.id }) {
                                        NavigationLink {
                                            EntryDetailView(entry: entry)
                                        } label: {
                                            EntryRow(entry: entry, showsProject: false)
                                        }.buttonStyle(.plain)
                                        Divider().padding(.leading, 48)
                                    }
                                }
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .navigationTitle("Project").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Edit project", systemImage: "pencil") { sheet = .edit }
                Button(project.isArchived ? "Restore project" : "Archive project", systemImage: "archivebox") {
                    project.isArchived.toggle()
                    do { try JournalStore.save(context) } catch { self.error = SaveError(error) }
                }
                Button("Delete project", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }.accessibilityLabel("Project actions")
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: ProjectEditorView(existing: project)
            case .entry: EntryEditorView(project: project)
            }
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete project and entries", role: .destructive) {
                do {
                    try JournalStore.delete(project, context: context)
                    dismiss()
                } catch { self.error = SaveError(error) }
            }
        } message: {
            Text(
                "All \(project.entries.count) build entries and their source links will be permanently removed. Daily reflections are kept."
            )
        }
        .journalError($error)
    }

    private var projectMetrics: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(project.entries.count)").font(.title2.weight(.semibold)).monospacedDigit()
                Text("build entries").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(days.count)").font(.title2.weight(.semibold)).monospacedDigit()
                Text("shipping days").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.title2.weight(.semibold))
                Text("started").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
