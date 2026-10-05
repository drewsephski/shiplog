import SwiftData
import XCTest

@testable import Shiplog

@MainActor final class PersistenceTests: XCTestCase {
    func testProjectAndEntryCreationEditingAndExport() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let project = try JournalStore.saveProject(
            context: context, name: "  Fieldnotes  ", overview: "Notes", repositoryURL: "")
        XCTAssertEqual(project.name, "Fieldnotes")
        try JournalStore.saveEntry(
            context: context, title: "  Shipped search ", detail: "Indexed notes", kind: .feature, date: .now,
            project: project)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<BuildEntry>()).first)
        XCTAssertEqual(entry.title, "Shipped search")
        XCTAssertEqual(entry.project?.id, project.id)
        XCTAssertEqual(project.entries.count, 1)
        try JournalStore.saveEntry(
            context: context, existing: entry, title: "Made search instant", detail: "Indexed locally",
            kind: .improvement, date: entry.occurredAt, project: project)
        XCTAssertEqual(entry.kind, .improvement)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuildEntry>()), 1)
        let data = try JournalExport.data(context: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(JournalExport.self, from: data)
        XCTAssertEqual(exported.entries.first?.record.title, "Made search instant")
        XCTAssertEqual(exported.entries.first?.record.projectID, project.id)
        XCTAssertEqual(exported.entries.first?.origin, "manual")
        XCTAssertEqual(exported.formatVersion, 2)
    }

    func testDeletingProjectCascadesEntriesAndEvidenceButKeepsReflections() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        let project = try JournalStore.saveProject(context: context, name: "Project", overview: "", repositoryURL: "")
        try JournalStore.saveEntry(
            context: context, title: "Release", detail: "", kind: .release, date: .now, project: project)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<BuildEntry>()).first)
        context.insert(
            SourceActivity(
                provider: "github", repositoryID: "repo", externalID: "repo:release:123", kind: "release", title: "v1", occurredAt: .now,
                entry: entry))
        try JournalStore.saveReflection(context: context, date: .now, text: "A good day.")
        try JournalStore.delete(project, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuildEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceActivity>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalSummary>()), 1)
    }

    func testReflectionUpsertAndRemoval() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        try JournalStore.saveReflection(context: context, date: .now, text: "First thought")
        try JournalStore.saveReflection(context: context, date: .now, text: "Updated thought")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalSummary>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JournalSummary>()).first?.text, "Updated thought")
        try JournalStore.saveReflection(context: context, date: .now, text: " \n ")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalSummary>()), 0)
    }

    func testValidationFailureDoesNotMutateExistingEntry() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        let project = try JournalStore.saveProject(context: context, name: "Project", overview: "", repositoryURL: "")
        try JournalStore.saveEntry(
            context: context, title: "Original", detail: "", kind: .fix, date: .now, project: project)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<BuildEntry>()).first)
        XCTAssertThrowsError(
            try JournalStore.saveEntry(
                context: context, existing: entry, title: "", detail: "", kind: .release, date: .now, project: project))
        XCTAssertEqual(entry.title, "Original")
        XCTAssertEqual(entry.kind, .fix)
    }

    func testEditingImportedWorkPreservesEvidenceInExport() throws {
        let container = try Persistence.container(inMemory: true)
        let context = container.mainContext
        let project = try JournalStore.saveProject(context: context, name: "Project", overview: "", repositoryURL: "")
        let entry = BuildEntry(title: "Imported work", kind: .feature, project: project, origin: .imported)
        context.insert(entry)
        context.insert(
            SourceActivity(
                provider: "github", repositoryID: "repo", externalID: "repo:pr:42", kind: "pullRequest", title: "Search", occurredAt: .now,
                entry: entry))
        try JournalStore.save(context)
        try JournalStore.saveEntry(
            context: context, existing: entry, title: "Shipped instant search", detail: "Reviewed by me",
            kind: .improvement, date: entry.occurredAt, project: project)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(JournalExport.self, from: JournalExport.data(context: context))
        XCTAssertEqual(export.entries.first?.origin, "imported")
        XCTAssertEqual(export.entries.first?.sources.first?.identity, EvidenceIdentity.make(provider: "github", repositoryID: "repo", kind: "pullRequest", externalID: "repo:pr:42"))
        XCTAssertEqual(export.entries.first?.record.title, "Shipped instant search")
    }

    func testDiskPersistenceSurvivesContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.store")
        let expectedID: UUID
        do {
            let container = try Persistence.container(url: url)
            let project = try JournalStore.saveProject(
                context: container.mainContext, name: "Persistent project", overview: "", repositoryURL: "")
            expectedID = project.id
            try JournalStore.saveEntry(
                context: container.mainContext, title: "Saved on disk", detail: "", kind: .feature, date: .now,
                project: project)
        }
        let restored = try Persistence.container(url: url)
        let project = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.id, expectedID)
        XCTAssertEqual(project.entries.first?.title, "Saved on disk")
    }

    func testProductionContainerStartsEmptyAndPreviewContainerIsSeparate() throws {
        let clean = try Persistence.container(inMemory: true)
        #if os(iOS) && DEBUG
            let preview = try PreviewFixtures.container()
        #else
            let preview = try Persistence.container(inMemory: true)
            let project = try JournalStore.saveProject(
                context: preview.mainContext, name: "Isolated example", overview: "", repositoryURL: "")
            try JournalStore.saveEntry(
                context: preview.mainContext, title: "Example entry", detail: "", kind: .feature, date: .now,
                project: project)
        #endif
        XCTAssertEqual(try clean.mainContext.fetchCount(FetchDescriptor<BuildEntry>()), 0)
        XCTAssertGreaterThan(try preview.mainContext.fetchCount(FetchDescriptor<BuildEntry>()), 0)
    }
}
