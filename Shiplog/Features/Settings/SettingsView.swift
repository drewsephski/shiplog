import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(GitHubConnection.self) private var connection
    @State private var exportURL: URL?
    @State private var exportError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ShiplogAppIcon()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shiplog").font(.headline)
                            Text("A journal for the things you build.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Connections") {
                    NavigationLink {
                        GitHubConnectionView()
                    } label: {
                        HStack {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Text(connection.isConnected ? "Connected" : "Connect").font(.caption).foregroundStyle(
                                .secondary)
                        }
                    }
                }
                Section {
                    Text(
                        "Your journal is cached on this iPhone. Connecting GitHub enables server imports and AI drafts for the repositories you select. Manual entries stay local."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    Button("Prepare journal export", systemImage: "square.and.arrow.up") {
                        do {
                            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                                "ShiplogExport", isDirectory: true)
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            let url = directory.appendingPathComponent("shiplog-journal.json")
                            try JournalExport.data(context: context).write(
                                to: url, options: [.atomic, .completeFileProtection])
                            exportURL = url
                        } catch { exportError = true }
                    }.accessibilityIdentifier("settings.export")
                    if let exportURL {
                        ShareLink(item: exportURL, preview: SharePreview("Shiplog journal")) {
                            Label("Share journal export", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Your journal")
                } footer: {
                    Text(
                        "JSON export includes projects, entries, source links, and reflections. Save a copy before deleting the app. Import is not available in this version."
                    )
                }
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    NavigationLink("Privacy") { PrivacyView() }
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Couldn’t export journal", isPresented: $exportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your journal is still saved. Please try preparing the export again.")
            }
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Local by default") {
                Text(
                    "Shiplog caches your journal in the app’s local database. Manual journaling works offline. There are no analytics, advertising, or tracking SDKs."
                )
            }
            Section("You choose what leaves") {
                Text(
                    "Sharing an export sends it to the destination you choose in the iOS share sheet. Opening a repository or source link opens that external website."
                )
            }
            Section("Backups and deletion") {
                Text(
                    "Your data may be included in device backups according to your iOS settings. Deleting the app removes its local journal. Export a copy first if you want to keep it."
                )
            }
            Section("GitHub and AI") {
                Text(
                    "Connecting GitHub is optional. You choose repositories and consent before repository context and activity are stored by Shiplog on Vercel/Neon and sent through OpenRouter to its selected model provider. Patches are optional. Generated-text edits are synchronized. Disconnect stops the agent; Delete server data removes your remote account, credentials, evidence, and history. GitHub installation permissions can be revoked in GitHub."
                )
            }
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}
