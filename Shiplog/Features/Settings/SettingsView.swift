import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var exportError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ShiplogMark()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shiplog").font(.headline)
                            Text("A journal for the things you build.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Connections") {
                    NavigationLink {
                        ConnectionInfoView()
                    } label: {
                        HStack {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Text("Coming later").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text(
                        "Build entries and reflections are stored locally on this iPhone. Shiplog doesn’t send your journal to a server or AI service."
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

struct ConnectionInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.largeTitle).accessibilityHidden(true)
                Eyebrow(text: "Coming later")
                Text("Your activity.\nThe bigger picture.").font(.largeTitle.weight(.bold)).tracking(-0.7)
                Text(
                    "A future GitHub connection will bring repository activity into Shiplog, so you can shape commits, pull requests, issues, and releases into a meaningful build story."
                )
                .foregroundStyle(.secondary)
                Divider()
                Text("For now, your journal starts with you.").font(.headline)
                Text(
                    "Log builds manually and add a repository link to your projects. No GitHub account is connected, and nothing is imported."
                )
                .foregroundStyle(.secondary)
                Text("Daily and weekly summary drafts are planned. Your own reflections are available today.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(24)
        }.navigationTitle("GitHub").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Local by default") {
                Text(
                    "Shiplog stores your journal in the app’s local database. It makes no network requests, collects no analytics, and includes no advertising or tracking SDKs."
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
            Section("Future connections") {
                Text(
                    "GitHub authentication and generated summaries are not connected in this version. Future services will require a clear opt-in before your journal is shared."
                )
            }
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}
