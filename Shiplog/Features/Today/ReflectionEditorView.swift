import SwiftUI

struct ReflectionEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State var text: String
    @State private var error: SaveError?
    @State private var initialText = ""
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What moved forward? What will you carry into tomorrow?", text: $text, axis: .vertical)
                        .lineLimit(8...20).accessibilityIdentifier("reflection.text")
                } header: {
                    Text(date, format: .dateTime.month(.wide).day())
                } footer: {
                    Text("A few words in your own voice. Clearing the text removes this reflection.")
                }
            }
            .navigationTitle("Daily reflection").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if text != initialText { confirmsDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try JournalStore.saveReflection(context: context, date: date, text: text)
                            dismiss()
                        } catch { self.error = SaveError(error) }
                    }.fontWeight(.semibold).accessibilityIdentifier("reflection.save")
                }
            }
            .onAppear { initialText = text }
            .interactiveDismissDisabled(text != initialText)
            .confirmationDialog("Discard this reflection?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .journalError($error)
        }
    }
}
