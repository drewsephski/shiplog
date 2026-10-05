import Foundation
import SwiftData

struct JournalExport: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let projects: [ProjectExport]
    let entries: [EntryExport]
    let reflections: [ReflectionExport]
    let evidence: [SourceExport]
    let repositories: [RepositoryExport]
    let generations: [GenerationExport]
    let checkpoints: [CheckpointExport]
    let pendingEdits: [JournalEdit]

    struct RepositoryExport: Codable {
        let ownerID: String
        let repositoryID: String
        let installationID: String
        let fullName: String
        let url: String
        let isPrivate: Bool
        let isEnabled: Bool
        let projectID: UUID?
    }
    struct GenerationExport: Codable {
        let id: UUID
        let ownerID: String
        let localDay: String
        let timeZone: String
        let evidenceHash: String
        let promptVersion: String
        let generatedAt: Date
    }
    struct CheckpointExport: Codable {
        let key: String
        let syncedAt: Date
        let evidenceHash: String
    }

    struct ProjectExport: Codable {
        let id: UUID
        let name: String
        let overview: String
        let repositoryURL: String?
        let createdAt: Date
        let isArchived: Bool
    }
    struct EntryExport: Codable {
        let record: EntryRecord
        let origin: String
        let createdAt: Date
        let updatedAt: Date
        let sources: [SourceExport]
        let remoteID: UUID?
        let ownerID: String?
        let confidence: Double?
        let evidenceIDs: [String]
    }
    struct SourceExport: Codable {
        let identity: String
        let provider: String
        let repositoryID: String
        let externalID: String
        let kind: String
        let title: String
        let url: String?
        let occurredAt: Date
    }
    struct ReflectionExport: Codable {
        let key: String
        let period: String
        let startDate: Date
        let endDate: Date
        let text: String
        let origin: String
        let updatedAt: Date
        let inputEntryIDs: [UUID]
        let evidenceIDs: [String]
        let remoteID: UUID?
    }

    @MainActor private static func sourceExport(_ source: SourceActivity) -> SourceExport {
        SourceExport(
            identity: source.identity, provider: source.provider, repositoryID: source.repositoryID,
            externalID: source.externalID,
            kind: source.kind, title: source.title, url: source.url, occurredAt: source.occurredAt)
    }

    @MainActor static func data(context: ModelContext) throws -> Data {
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try context.fetch(FetchDescriptor<BuildEntry>(sortBy: [SortDescriptor(\.occurredAt)]))
        let summaries = try context.fetch(FetchDescriptor<JournalSummary>(sortBy: [SortDescriptor(\.startDate)]))
        let allSources = try context.fetch(FetchDescriptor<SourceActivity>())
        let repositories = try context.fetch(FetchDescriptor<ConnectedRepository>())
        let generations = try context.fetch(FetchDescriptor<GenerationRun>())
        let checkpoints = try context.fetch(FetchDescriptor<SyncCheckpoint>())
        let mutations = try context.fetch(FetchDescriptor<JournalMutation>())
        let export = JournalExport(
            formatVersion: 2, exportedAt: .now,
            projects: projects.map {
                ProjectExport(
                    id: $0.id, name: $0.name, overview: $0.overview, repositoryURL: $0.repositoryURL,
                    createdAt: $0.createdAt, isArchived: $0.isArchived)
            },
            entries: entries.map { entry in
                EntryExport(
                    record: entry.record, origin: entry.originRawValue, createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt,
                    sources: (entry.sources
                        + allSources.filter { source in entry.evidenceIDs.contains(source.identity) })
                        .reduce(into: [String: SourceActivity]()) { $0[$1.identity] = $1 }.values.sorted {
                            $0.identity < $1.identity
                        }.map(sourceExport),
                    remoteID: entry.remoteID, ownerID: entry.ownerID, confidence: entry.confidence,
                    evidenceIDs: entry.evidenceIDs)
            },
            reflections: summaries.map {
                ReflectionExport(
                    key: $0.key, period: $0.periodRawValue, startDate: $0.startDate,
                    endDate: $0.endDate, text: $0.text, origin: $0.originRawValue,
                    updatedAt: $0.updatedAt, inputEntryIDs: $0.inputEntryIDs, evidenceIDs: $0.evidenceIDs,
                    remoteID: $0.remoteID)
            },
            evidence: allSources.sorted { $0.identity < $1.identity }.map(sourceExport),
            repositories: repositories.map {
                RepositoryExport(
                    ownerID: $0.ownerID, repositoryID: $0.repositoryID, installationID: $0.installationID,
                    fullName: $0.fullName, url: $0.url, isPrivate: $0.isPrivate, isEnabled: $0.isEnabled,
                    projectID: $0.project?.id)
            },
            generations: generations.map {
                GenerationExport(
                    id: $0.id, ownerID: $0.ownerID, localDay: $0.localDay, timeZone: $0.timeZone,
                    evidenceHash: $0.evidenceHash, promptVersion: $0.promptVersion, generatedAt: $0.generatedAt)
            },
            checkpoints: checkpoints.map {
                CheckpointExport(key: $0.key, syncedAt: $0.syncedAt, evidenceHash: $0.evidenceHash)
            },
            pendingEdits: try mutations.map { try AgentCoding.decoder().decode(JournalEdit.self, from: $0.payload) })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }
}
