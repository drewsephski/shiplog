import SwiftUI

struct ProjectEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let existing: Project?
    let onSaved: ((Project) -> Void)?
    @State private var name: String
    @State private var overview: String
    @State private var repositoryURL: String
    @State private var error: SaveError?
    @State private var confirmsDiscard = false

    init(existing: Project? = nil, onSaved: ((Project) -> Void)? = nil) {
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _overview = State(initialValue: existing?.overview ?? "")
        _repositoryURL = State(initialValue: existing?.repositoryURL ?? "")
    }
    private var isDirty: Bool {
        name != (existing?.name ?? "") || overview != (existing?.overview ?? "")
            || repositoryURL != (existing?.repositoryURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $name).accessibilityIdentifier("project.name")
                    TextField("What are you building?", text: $overview, axis: .vertical)
                        .lineLimit(3...8).accessibilityIdentifier("project.overview")
                } header: {
                    Text("The project")
                } footer: {
                    Text("A repository, a product, or a side project. Give it a name you recognize.")
                }
                Section {
                    TextField("https://github.com/you/project", text: $repositoryURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("project.repositoryURL")
                } header: {
                    Text("Repository URL · optional")
                } footer: {
                    Text("A reference link for now. Adding a URL won’t connect or import a repository.")
                }
            }
            .navigationTitle(existing == nil ? "New project" : "Edit project").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmsDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let project = try JournalStore.saveProject(
                                context: context, existing: existing, name: name,
                                overview: overview, repositoryURL: repositoryURL)
                            onSaved?(project)
                            dismiss()
                        } catch { self.error = SaveError(error) }
                    }.fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("project.save")
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard this project draft?", isPresented: $confirmsDiscard, titleVisibility: .visible)
            {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .journalError($error)
        }
    }
}
