import Foundation
import SwiftData

enum ShiplogSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Project.self, BuildEntry.self, SourceActivity.self, JournalSummary.self]
    }

    @Model final class Project {
        @Attribute(.unique) var id: UUID
        var name: String
        var overview: String
        var repositoryURL: String?
        var createdAt: Date
        var isArchived: Bool
        @Relationship(deleteRule: .cascade, inverse: \BuildEntry.project)
        var entries: [BuildEntry] = []

        init(
            id: UUID = UUID(), name: String, overview: String = "", repositoryURL: String? = nil,
            createdAt: Date = .now, isArchived: Bool = false
        ) {
            self.id = id
            self.name = name
            self.overview = overview
            self.repositoryURL = repositoryURL
            self.createdAt = createdAt
            self.isArchived = isArchived
        }
    }

    @Model final class BuildEntry {
        @Attribute(.unique) var id: UUID
        var title: String
        var detail: String
        var kindRawValue: String
        var occurredAt: Date
        var createdAt: Date
        var updatedAt: Date
        var originRawValue: String
        var project: Project?
        @Relationship(deleteRule: .cascade, inverse: \SourceActivity.entry)
        var sources: [SourceActivity] = []

        var kind: BuildKind { BuildKind(rawValue: kindRawValue) ?? .improvement }
        var origin: EntryOrigin { EntryOrigin(rawValue: originRawValue) ?? .manual }

        init(
            id: UUID = UUID(), title: String, detail: String = "", kind: BuildKind = .feature,
            occurredAt: Date = .now, project: Project? = nil, origin: EntryOrigin = .manual
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.kindRawValue = kind.rawValue
            self.occurredAt = occurredAt
            self.createdAt = .now
            self.updatedAt = .now
            self.originRawValue = origin.rawValue
            self.project = project
        }
    }

    /// Provider identity and evidence are retained separately from the journal's narrative.
    @Model final class SourceActivity {
        @Attribute(.unique) var identity: String
        var provider: String
        var externalID: String
        var kind: String
        var title: String
        var url: String?
        var occurredAt: Date
        var entry: BuildEntry?

        init(
            provider: String, externalID: String, kind: String, title: String,
            url: String? = nil, occurredAt: Date, entry: BuildEntry? = nil
        ) {
            self.identity = "\(provider):\(externalID)"
            self.provider = provider
            self.externalID = externalID
            self.kind = kind
            self.title = title
            self.url = url
            self.occurredAt = occurredAt
            self.entry = entry
        }
    }

    @Model final class JournalSummary {
        @Attribute(.unique) var key: String
        var periodRawValue: String
        var startDate: Date
        var endDate: Date
        var text: String
        var originRawValue: String
        var updatedAt: Date
        /// Entry IDs describe exactly which work informed a future generated draft.
        var inputEntryIDs: [UUID]

        init(
            key: String, period: SummaryPeriod, startDate: Date, endDate: Date,
            text: String, origin: SummaryOrigin = .manual, inputEntryIDs: [UUID] = []
        ) {
            self.key = key
            self.periodRawValue = period.rawValue
            self.startDate = startDate
            self.endDate = endDate
            self.text = text
            self.originRawValue = origin.rawValue
            self.updatedAt = .now
            self.inputEntryIDs = inputEntryIDs
        }
    }
}
