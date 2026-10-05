import Foundation
import SwiftData

enum Persistence {
    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ShiplogSchemaV1.self)
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
        if clean.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.text = clean
            existing.originRawValue = SummaryOrigin.manual.rawValue
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
        context.delete(model)
        try save(context)
    }

    static func save(_ context: ModelContext) throws {
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
    }
}
