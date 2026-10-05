import Foundation
import SwiftData

enum ShiplogSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            Project.self, BuildEntry.self, SourceActivity.self, JournalSummary.self, ConnectedRepository.self,
            SyncCheckpoint.self, GenerationRun.self, JournalMutation.self,
        ]
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
        var remoteID: UUID? = nil
        var ownerID: String? = nil
        var localDay: String? = nil
        var confidence: Double? = nil
        var evidenceIDs: [String] = []
        var generationID: UUID? = nil
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
        var repositoryID: String = ""
        var externalID: String
        var kind: String
        var title: String
        var url: String?
        var occurredAt: Date
        var entry: BuildEntry?

        init(
            provider: String, repositoryID: String, externalID: String, kind: String, title: String,
            url: String? = nil, occurredAt: Date, entry: BuildEntry? = nil
        ) {
            self.identity = EvidenceIdentity.make(
                provider: provider, repositoryID: repositoryID, kind: kind, externalID: externalID)
            self.repositoryID = repositoryID
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
        var remoteID: UUID? = nil
        var ownerID: String? = nil
        var evidenceIDs: [String] = []

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

    @Model final class ConnectedRepository {
        @Attribute(.unique) var key: String
        var ownerID: String
        var repositoryID: String
        var installationID: String
        var fullName: String
        var url: String
        var isPrivate: Bool
        var isEnabled: Bool
        var project: Project?
        init(
            ownerID: String, repositoryID: String, installationID: String, fullName: String, url: String,
            isPrivate: Bool, project: Project
        ) {
            self.key = "\(ownerID):\(repositoryID)"
            self.ownerID = ownerID
            self.repositoryID = repositoryID
            self.installationID = installationID
            self.fullName = fullName
            self.url = url
            self.isPrivate = isPrivate
            self.isEnabled = true
            self.project = project
        }
    }
    @Model final class SyncCheckpoint {
        @Attribute(.unique) var key: String
        var syncedAt: Date
        var evidenceHash: String
        init(key: String, syncedAt: Date, evidenceHash: String) {
            self.key = key
            self.syncedAt = syncedAt
            self.evidenceHash = evidenceHash
        }
    }
    @Model final class GenerationRun {
        @Attribute(.unique) var id: UUID
        var ownerID: String
        var localDay: String
        var timeZone: String
        var evidenceHash: String
        var promptVersion: String
        var generatedAt: Date
        init(
            id: UUID, ownerID: String, localDay: String, timeZone: String, evidenceHash: String, promptVersion: String,
            generatedAt: Date
        ) {
            self.id = id
            self.ownerID = ownerID
            self.localDay = localDay
            self.timeZone = timeZone
            self.evidenceHash = evidenceHash
            self.promptVersion = promptVersion
            self.generatedAt = generatedAt
        }
    }
    /// Persistent outbox: edits/deletions survive offline use and response loss.
    @Model final class JournalMutation {
        @Attribute(.unique) var id: UUID
        var ownerID: String
        var targetID: UUID
        var targetType: String
        var payload: Data
        var createdAt: Date
        init(id: UUID, ownerID: String, targetID: UUID, targetType: String, payload: Data) {
            self.id = id
            self.ownerID = ownerID
            self.targetID = targetID
            self.targetType = targetType
            self.payload = payload
            self.createdAt = .now
        }
    }
}

typealias Project = ShiplogSchemaV2.Project
typealias BuildEntry = ShiplogSchemaV2.BuildEntry
typealias SourceActivity = ShiplogSchemaV2.SourceActivity
typealias JournalSummary = ShiplogSchemaV2.JournalSummary
typealias ConnectedRepository = ShiplogSchemaV2.ConnectedRepository
typealias SyncCheckpoint = ShiplogSchemaV2.SyncCheckpoint
typealias GenerationRun = ShiplogSchemaV2.GenerationRun
typealias JournalMutation = ShiplogSchemaV2.JournalMutation

enum ShiplogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ShiplogSchemaV1.self, ShiplogSchemaV2.self] }
    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: ShiplogSchemaV1.self, toVersion: ShiplogSchemaV2.self, willMigrate: nil,
                didMigrate: { context in
                    let sources = try context.fetch(FetchDescriptor<ShiplogSchemaV2.SourceActivity>())
                    for source in sources {
                        source.repositoryID = source.entry?.project?.repositoryURL ?? "legacy"
                        source.identity = EvidenceIdentity.make(
                            provider: source.provider, repositoryID: source.repositoryID, kind: source.kind,
                            externalID: source.externalID)
                    }
                    try context.save()
                })
        ]
    }
}
