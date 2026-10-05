import SwiftData
import SwiftUI

struct EntryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var projects: [Project]
    let existing: BuildEntry?
    @State private var title: String
    @State private var detail: String
    @State private var kind: BuildKind
    @State private var date: Date
    @State private var projectID: UUID?
    @State private var showingProjectEditor = false
    @State private var error: SaveError?
    @State private var confirmsDiscard = false
    private let initialTitle: String
    private let initialDetail: String
    private let initialKind: BuildKind
    private let initialDate: Date
    private let initialProjectID: UUID?

    init(existing: BuildEntry? = nil, project: Project? = nil, date: Date = .now) {
        self.existing = existing
        let initialDate = existing?.occurredAt ?? date
        let initialProjectID = existing?.project?.id ?? project?.id
        initialTitle = existing?.title ?? ""
        initialDetail = existing?.detail ?? ""
        initialKind = existing?.kind ?? .feature
        self.initialDate = initialDate
        self.initialProjectID = initialProjectID
        _title = State(initialValue: existing?.title ?? "")
        _detail = State(initialValue: existing?.detail ?? "")
        _kind = State(initialValue: existing?.kind ?? .feature)
        _date = State(initialValue: initialDate)
        _projectID = State(initialValue: initialProjectID)
    }
    private var isDirty: Bool {
        title != initialTitle || detail != initialDetail || kind != initialKind || date != initialDate
            || projectID != initialProjectID
    }
    private var selectableProjects: [Project] {
        projects.filter { !$0.isArchived || $0.id == existing?.project?.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you ship?", text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold)).lineLimit(2...4)
                        .accessibilityIdentifier("entry.title")
                    TextField("The change, the why, the outcome…", text: $detail, axis: .vertical)
                        .lineLimit(4...12).accessibilityIdentifier("entry.detail")
                } header: {
                    Text("The meaningful part")
                } footer: {
                    Text("Describe a piece of work, rather than every commit.")
                }
                Section("Project") {
                    if selectableProjects.isEmpty {
                        Button {
                            showingProjectEditor = true
                        } label: {
                            Label("Create your first project", systemImage: "plus")
                        }.accessibilityIdentifier("entry.createProject")
                    } else {
                        Picker("Project", selection: $projectID) {
                            Text("Choose a project").tag(Optional<UUID>.none)
                            ForEach(selectableProjects) { Text($0.name).tag(Optional($0.id)) }
                        }.disabled(existing?.remoteID != nil).accessibilityIdentifier("entry.project")
                        Button("New project", systemImage: "plus") { showingProjectEditor = true }
                    }
                }
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(BuildKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    DatePicker("Shipped", selection: $date, in: ...Date.now)
                } footer: {
                    Text(
                        existing?.remoteID == nil
                            ? "Recorded by you. You can edit this entry at any time."
                            : "Your edits are preserved on later generations. The repository stays linked to its evidence."
                    )
                }
            }
            .navigationTitle(existing == nil ? "Log a build" : "Edit build")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmsDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectID == nil)
                        .accessibilityIdentifier("entry.save")
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard this draft?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .journalError($error)
            .sheet(isPresented: $showingProjectEditor) {
                ProjectEditorView { project in projectID = project.id }
            }
        }
    }
    private func save() {
        do {
            try JournalStore.saveEntry(
                context: context, existing: existing, title: title, detail: detail,
                kind: kind, date: date, project: projects.first { $0.id == projectID })
            dismiss()
        } catch { self.error = SaveError(error) }
    }
}
