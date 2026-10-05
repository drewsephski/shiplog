import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var adding = false
    @State private var search = ""
    private var filtered: [Project] {
        projects.filter {
            search.isEmpty || $0.name.localizedStandardContains(search) || $0.overview.localizedStandardContains(search)
        }
    }

    var body: some View {
        List {
            if projects.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    JournalEmptyState(
                        symbol: "square.stack.3d.up", title: "Every build has a home.",
                        message: "Create a project to keep its work, decisions, and releases together.")
                    PrimaryAction(title: "Create a project", symbol: "plus") { adding = true }
                        .accessibilityIdentifier("projects.create")
                }.listRowSeparator(.hidden)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                projectSection("Active", archived: false)
                if filtered.contains(where: \.isArchived) { projectSection("Archived", archived: true) }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Projects")
        .searchable(text: $search, prompt: "Find a project")
        .toolbar {
            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New project").accessibilityIdentifier("projects.add")
        }
        .sheet(isPresented: $adding) { ProjectEditorView() }
    }

    private func projectSection(_ title: String, archived: Bool) -> some View {
        Section(title) {
            ForEach(filtered.filter { $0.isArchived == archived }) { project in
                NavigationLink {
                    ProjectDetailView(project: project)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: archived ? "archivebox" : "square.stack.3d.up")
                            .font(.title3).frame(width: 30, height: 34).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(project.name).font(.headline)
                            if !project.overview.isEmpty {
                                Text(project.overview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            let latest = project.entries.max { $0.occurredAt < $1.occurredAt }
                            if let latest {
                                Text("Last built \(latest.occurredAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Ready for its first build").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 12)
                }
            }
        }
    }
}
