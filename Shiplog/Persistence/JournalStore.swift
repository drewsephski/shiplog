import Foundation
import SwiftData

enum Persistence {
    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ShiplogSchemaV2.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema, migrationPlan: ShiplogMigrationPlan.self,
            configurations: [configuration])
    }
}

/// Explicit saves keep a failed editor operation from leaking into other screens.
@MainActor enum JournalStore {
    @discardableResult static func saveProject(
        context: ModelContext, existing: Project? = nil, name: String,
        overview: String, repositoryURL: String
    ) throws -> Project {
        let url = try JournalValidation.project(name: name, overview: overview, repositoryURL: repositoryURL)
        let project = existing ?? Project(name: name)
        project.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.overview = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        project.repositoryURL = url
        if existing == nil { context.insert(project) }
        try save(context)
        return project
    }

    static func saveEntry(
        context: ModelContext, existing: BuildEntry? = nil, title: String,
        detail: String, kind: BuildKind, date: Date, project: Project?
    ) throws {
        try JournalValidation.entry(title: title, detail: detail, projectID: project?.id, date: date)
        let entry = existing ?? BuildEntry(title: title)
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.kindRawValue = kind.rawValue
        entry.occurredAt = date
        entry.project = project
        entry.updatedAt = .now
        if let remoteID = entry.remoteID, let ownerID = entry.ownerID {
            entry.originRawValue = EntryOrigin.userEditedGenerated.rawValue
            try JournalSyncStore.enqueue(JournalEdit(mutationID: UUID(), targetID: remoteID, targetType: "entry", deleted: false,
                title: entry.title, detail: entry.detail, kind: entry.kind, occurredAt: entry.occurredAt), ownerID: ownerID, context: context)
        }
        if existing == nil { context.insert(entry) }
        try save(context)
    }

    static func saveReflection(
        context: ModelContext, date: Date, text: String,
        calendar: Calendar = .current
    ) throws {
        guard text.count <= 20_000 else { throw JournalValidationError.detailTooLong }
        let key = JournalLogic.reflectionKey(for: date, calendar: calendar)
        let existing = try context.fetch(FetchDescriptor<JournalSummary>(predicate: #Predicate { $0.key == key })).first
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remoteID = existing?.remoteID, let ownerID = existing?.ownerID {
            try JournalSyncStore.enqueue(JournalEdit(mutationID: UUID(), targetID: remoteID, targetType: "narrative", deleted: clean.isEmpty,
                title: nil, detail: clean, kind: nil, occurredAt: nil), ownerID: ownerID, context: context)
        }
        if clean.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.text = clean
            existing.originRawValue = (existing.remoteID == nil ? SummaryOrigin.manual : .userEditedGenerated).rawValue
            existing.inputEntryIDs = []
            existing.updatedAt = .now
        } else {
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            context.insert(JournalSummary(key: key, period: .daily, startDate: start, endDate: end, text: clean))
        }
        try save(context)
    }

    static func delete<T: PersistentModel>(_ model: T, context: ModelContext) throws {
        if let entry = model as? BuildEntry { try suppress(entry, context: context) }
        if let project = model as? Project {
            for entry in project.entries { try suppress(entry, context: context) }
        }
        context.delete(model)
        try save(context)
    }

    private static func suppress(_ entry: BuildEntry, context: ModelContext) throws {
        guard let remoteID = entry.remoteID, let ownerID = entry.ownerID else { return }
        try JournalSyncStore.enqueue(JournalEdit(mutationID: UUID(), targetID: remoteID, targetType: "entry", deleted: true,
            title: nil, detail: nil, kind: nil, occurredAt: nil), ownerID: ownerID, context: context)
    }

    static func save(_ context: ModelContext) throws {
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
    }
}
