import SwiftData
import XCTest

@testable import Shiplog

@MainActor final class AutonomousJournalTests: XCTestCase {
    private let owner = "verified-user"
    private let entryID = UUID()
    private let journalID = UUID()
    private var evidenceID: String { EvidenceIdentity.make(provider: "github", repositoryID: "12", kind: "commit", externalID: "abc") }

    private func journal(title: String = "Improved onboarding", evidenceIDs: [String]? = nil) -> AgentJournal {
        let date = Date.now
        let day = AgentDay(date: date)
        return AgentJournal(userID: owner, day: day.day, timeZone: day.timeZone, status: "completed", errorCode: nil,
            repositories: [.init(id: "12", installationID: "99", name: "Shiplog", fullName: "test/shiplog", url: "https://github.com/test/shiplog",
                description: "A journal", isPrivate: true, isEnabled: true, defaultBranch: "main", checkpoint: date)],
            entries: [.init(id: entryID, repositoryID: "12", title: title, detail: "Simplified the connection screen.", kind: .improvement,
                confidence: 0.9, evidenceIDs: evidenceIDs ?? [self.evidenceID], occurredAt: date, userEdited: false, userDeleted: false)],
            evidence: [.init(id: self.evidenceID, repositoryID: "12", externalID: "abc", kind: "commit", title: "Simplify onboarding",
                occurredAt: date, url: "https://github.com/test/shiplog/commit/abc", actorID: "1")],
            narrative: .init(id: journalID, text: "I simplified onboarding today.", userEdited: false, evidenceIDs: [self.evidenceID]),
            generation: .init(id: journalID, evidenceHash: "hash", promptVersion: "journal-synthesis-1", generatedAt: date))
    }

    func testImportMatchesProjectAndIsIdempotentWithExactProvenance() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        let project = try JournalStore.saveProject(context: context, name: "My project name", overview: "My overview", repositoryURL: "https://github.com/test/shiplog")
        try JournalSyncStore.merge(journal(), ownerID: owner, context: context)
        try JournalSyncStore.merge(journal(), ownerID: owner, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
        XCTAssertEqual(project.name, "My project name")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuildEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceActivity>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GenerationRun>()), 1)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<BuildEntry>()).first)
        XCTAssertEqual(entry.origin, .generated)
        XCTAssertEqual(entry.evidenceIDs, [evidenceID])
        XCTAssertEqual(try JournalSyncStore.evidence(for: entry, context: context).first?.identity, evidenceID)
        let export = try AgentCoding.decoder().decode(JournalExport.self, from: JournalExport.data(context: context))
        XCTAssertEqual(export.entries.first?.sources.first?.repositoryID, "12")
        XCTAssertEqual(export.entries.first?.confidence, 0.9)
        XCTAssertEqual(export.generations.first?.promptVersion, "journal-synthesis-1")
    }

    func testEditedDraftAndManualReflectionAreNeverOverwritten() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        try JournalStore.saveReflection(context: context, date: .now, text: "My handwritten reflection.")
        try JournalSyncStore.merge(journal(), ownerID: owner, context: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<BuildEntry>()).first)
        try JournalStore.saveEntry(context: context, existing: entry, title: "My precise words", detail: "My reason", kind: .fix, date: entry.occurredAt, project: entry.project)
        try JournalSyncStore.merge(journal(title: "A different AI title"), ownerID: owner, context: context)
        XCTAssertEqual(entry.title, "My precise words")
        XCTAssertEqual(entry.origin, .userEditedGenerated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalSummary>()).first?.text, "My handwritten reflection.")
        let mutation = try XCTUnwrap(context.fetch(FetchDescriptor<JournalMutation>()).first)
        let edit = try AgentCoding.decoder().decode(JournalEdit.self, from: mutation.payload)
        XCTAssertEqual(edit.title, "My precise words")
        XCTAssertEqual(edit.targetID, entryID)
    }

    func testOfflineDeletionAndClearedGeneratedStoryAreNotResurrected() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        try JournalSyncStore.merge(journal(), ownerID: owner, context: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<BuildEntry>()).first)
        try JournalStore.delete(entry, context: context)
        try JournalStore.saveReflection(context: context, date: .now, text: "")
        try JournalSyncStore.merge(journal(), ownerID: owner, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuildEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalSummary>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalMutation>()), 2)
    }

    func testInvalidProvenanceAndWrongIdentityDoNotMutateStore() throws {
        let container = try Persistence.container(inMemory: true)
        XCTAssertThrowsError(try JournalSyncStore.merge(journal(evidenceIDs: ["invented"]), ownerID: owner, context: container.mainContext))
        XCTAssertThrowsError(try JournalSyncStore.merge(journal(), ownerID: "someone-else", context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<BuildEntry>()), 0)
    }

    func testEvidenceIdentityScopesAllComponentsAndEscapesSeparators() {
        XCTAssertEqual(EvidenceIdentity.make(provider: "github", repositoryID: "12", kind: "issue", externalID: "42:closed"), "github:12:issue:42%3Aclosed")
        XCTAssertNotEqual(evidenceID, EvidenceIdentity.make(provider: "github", repositoryID: "13", kind: "commit", externalID: "abc"))
        XCTAssertNotEqual(evidenceID, EvidenceIdentity.make(provider: "github", repositoryID: "12", kind: "issue", externalID: "abc"))
    }

    func testV1DiskStoreMigratesWithoutLosingWritingOrRelationships() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.store")
        let projectID = try seedV1(at: url)
        let migrated = try Persistence.container(url: url)
        let project = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.id, projectID)
        XCTAssertEqual(project.entries.first?.title, "My original build")
        XCTAssertEqual(project.entries.first?.sources.first?.repositoryID, "https://github.com/test/shiplog")
        XCTAssertEqual(project.entries.first?.sources.first?.identity,
            EvidenceIdentity.make(provider: "github", repositoryID: "https://github.com/test/shiplog", kind: "commit", externalID: "legacy-id"))
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<JournalSummary>()).first?.text, "My original reflection")
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<JournalMutation>()), 0)
    }

    private func seedV1(at url: URL) throws -> UUID {
        let schema = Schema(versionedSchema: ShiplogSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let project = ShiplogSchemaV1.Project(name: "Original", repositoryURL: "https://github.com/test/shiplog")
        let entry = ShiplogSchemaV1.BuildEntry(title: "My original build", project: project)
        let source = ShiplogSchemaV1.SourceActivity(provider: "github", externalID: "legacy-id", kind: "commit", title: "Original evidence", occurredAt: .now, entry: entry)
        let summary = ShiplogSchemaV1.JournalSummary(key: JournalLogic.reflectionKey(for: .now), period: .daily, startDate: .now, endDate: .now, text: "My original reflection")
        container.mainContext.insert(project)
        container.mainContext.insert(entry)
        container.mainContext.insert(source)
        container.mainContext.insert(summary)
        try container.mainContext.save()
        return project.id
    }
}
