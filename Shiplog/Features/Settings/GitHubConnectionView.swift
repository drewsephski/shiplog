import SwiftData
import SwiftUI

struct ConnectionStatusView: View {
    @Environment(GitHubConnection.self) private var connection
    var body: some View {
        if connection.isBusy {
            ProgressView(connection.status).font(.subheadline).accessibilityIdentifier("connection.progress")
        } else if let error = connection.errorMessage {
            Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("connection.error")
        } else if connection.isConnected && !connection.status.isEmpty {
            Text(connection.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct GitHubConnectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(GitHubConnection.self) private var connection
    @Query private var repositories: [ConnectedRepository]
    @State private var confirmsDisconnect = false
    @State private var confirmsDelete = false
    @State private var finalizeTime = Date.now

    var body: some View {
        List {
            Section {
                Text("Your activity.\nThe bigger picture.").font(.title.weight(.bold)).tracking(-0.7)
                Text("Meaningful build entries and a daily story, backed by your own source activity.").foregroundStyle(.secondary)
                ConnectionStatusView()
                if let session = connection.session {
                    LabeledContent("Connected as", value: session.login)
                    Button("Analyze today", systemImage: "arrow.clockwise") {
                        Task { await connection.refresh(context: context, generate: true) }
                    }.disabled(connection.isBusy)
                }
                Button(connection.isConnected ? "Change selected repositories" : "Connect GitHub", systemImage: "chevron.left.forwardslash.chevron.right") {
                    Task { await connection.connect(context: context) }
                }.disabled(connection.isBusy).accessibilityIdentifier("connection.connect")
            }
            if connection.isConnected {
                Section("Selected repositories") {
                    ForEach(repositories.filter { $0.ownerID == connection.session?.userID && $0.isEnabled }, id: \.key) { repo in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(repo.fullName)
                            Text(repo.isPrivate ? "Private · Selected by you" : "Public").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    DatePicker("Daily journal time", selection: $finalizeTime, displayedComponents: .hourAndMinute)
                    Button("Save journal time") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: finalizeTime)
                        Task { await connection.updateSchedule(minute: (parts.hour ?? 20) * 60 + (parts.minute ?? 0)) }
                    }.disabled(connection.isBusy)
                } header: { Text("Your evening journal") } footer: {
                    Text("The server generates your journal around this time in your current time zone, even with Shiplog closed. Activity can update the draft throughout the day.")
                }
            }
            Section("What is shared") {
                Text("Your selected repository metadata, README, manifests, architecture excerpts, commit messages, PR and issue text, changed filenames, and diff statistics go to the Shiplog server and OpenRouter’s selected AI model provider.")
                Text("Code patches require a separate opt-in when choosing repositories. Whole repositories aren’t uploaded. AI drafts retain their source links and can be wrong; review them. Confidence describes model certainty, not independent verification.")
                Text("Manual entries stay local. Edits to generated entries and stories are synchronized so the server can preserve your words. No analytics or advertising.")
            }
            if connection.isConnected {
                Section {
                    Button("Disconnect GitHub", role: .destructive) { confirmsDisconnect = true }
                    Button("Delete Shiplog server data", role: .destructive) { confirmsDelete = true }
                } footer: {
                    Text("Disconnect stops imports and scheduled work, and removes stored GitHub credentials. Server history is retained; reconnect to delete it. Delete server data removes your account, credentials, evidence, and generated history. Your local journal is retained. Manage or uninstall the GitHub App in GitHub to revoke its installation permissions.")
                }
            }
        }
        .navigationTitle("GitHub").navigationBarTitleDisplayMode(.inline)
        .task {
            if let minute = connection.session?.finalizeMinute {
                finalizeTime = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            }
        }
        .confirmationDialog("Disconnect GitHub?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await connection.disconnect(deleteData: false, context: context) } }
        }
        .confirmationDialog("Delete all Shiplog server data?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete server data", role: .destructive) { Task { await connection.disconnect(deleteData: true, context: context) } }
        } message: { Text("This can’t be undone. Your local journal remains on this iPhone.") }
    }
}
