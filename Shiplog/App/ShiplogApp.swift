import OSLog
import SwiftData
import SwiftUI

@main struct ShiplogApp: App {
    @State private var container: ModelContainer?
    @State private var storeFailed = false
    private static let logger = Logger(subsystem: "com.shiplog.Shiplog", category: "persistence")

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    AppRootView().modelContainer(container)
                } else if storeFailed {
                    ContentUnavailableView {
                        Label("Your journal couldn’t open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your data hasn’t been erased. Try opening your journal again.")
                    } actions: {
                        Button("Try again") { openStore() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("Opening your journal…").task { openStore() }
                }
            }
            .tint(.primary)
        }
    }

    @MainActor private func openStore() {
        storeFailed = false
        do {
            #if DEBUG
                let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                let previewing = ProcessInfo.processInfo.arguments.contains("--preview-data")
                let newContainer = try Persistence.container(inMemory: testing || previewing)
                if previewing { try PreviewFixtures.populate(newContainer.mainContext) }
            #else
                let newContainer = try Persistence.container()
            #endif
            newContainer.mainContext.autosaveEnabled = false
            container = newContainer
        } catch {
            Self.logger.error("Store initialization failed: \(String(describing: error), privacy: .private)")
            storeFailed = true
        }
    }
}
