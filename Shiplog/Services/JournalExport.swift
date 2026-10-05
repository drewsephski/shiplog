import Foundation
import SwiftData

struct JournalExport: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let projects: [ProjectExport]
    let entries: [EntryExport]
    let reflections: [ReflectionExport]

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
    }
    struct SourceExport: Codable {
        let identity: String
        let provider: String
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
    }

    @MainActor static func data(context: ModelContext) throws -> Data {
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try context.fetch(FetchDescriptor<BuildEntry>(sortBy: [SortDescriptor(\.occurredAt)]))
        let summaries = try context.fetch(FetchDescriptor<JournalSummary>(sortBy: [SortDescriptor(\.startDate)]))
        let export = JournalExport(
            formatVersion: 1, exportedAt: .now,
            projects: projects.map {
                ProjectExport(
                    id: $0.id, name: $0.name, overview: $0.overview, repositoryURL: $0.repositoryURL,
                    createdAt: $0.createdAt, isArchived: $0.isArchived)
            },
            entries: entries.map {
                EntryExport(
                    record: $0.record, origin: $0.originRawValue, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    sources: $0.sources.map {
                        SourceExport(
                            identity: $0.identity, provider: $0.provider, externalID: $0.externalID,
                            kind: $0.kind, title: $0.title, url: $0.url, occurredAt: $0.occurredAt)
                    })
            },
            reflections: summaries.map {
                ReflectionExport(
                    key: $0.key, period: $0.periodRawValue, startDate: $0.startDate,
                    endDate: $0.endDate, text: $0.text, origin: $0.originRawValue,
                    updatedAt: $0.updatedAt, inputEntryIDs: $0.inputEntryIDs)
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }
}
