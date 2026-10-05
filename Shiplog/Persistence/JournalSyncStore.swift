import Foundation
import SwiftData

@MainActor enum JournalSyncStore {
    static func merge(_ journal: AgentJournal, ownerID: String, context: ModelContext) throws {
        try validate(journal, ownerID: ownerID)
        // A pending server job must never retire the last successfully generated cache.
        guard let generation = journal.generation else { return }
        do {
            let projects = try context.fetch(FetchDescriptor<Project>())
            let connections = try context.fetch(FetchDescriptor<ConnectedRepository>())
            let allEntries = try context.fetch(FetchDescriptor<BuildEntry>())
            let sources = try context.fetch(FetchDescriptor<SourceActivity>())
            let mutations = try context.fetch(FetchDescriptor<JournalMutation>())
            let suppressed = Set(mutations.filter { $0.ownerID == ownerID }.map(\.targetID))
            var projectMap: [String: Project] = [:]
            for repo in journal.repositories {
                let connection = connections.first { $0.ownerID == ownerID && $0.repositoryID == repo.id }
                let project =
                    connection?.project ?? projects.first { $0.repositoryURL == repo.url }
                    ?? Project(name: repo.name, overview: repo.description, repositoryURL: repo.url)
                if project.modelContext == nil { context.insert(project) }
                projectMap[repo.id] = project
                if let connection {
                    connection.project = project
                    connection.installationID = repo.installationID
                    connection.fullName = repo.fullName
                    connection.url = repo.url
                    connection.isPrivate = repo.isPrivate
                    connection.isEnabled = repo.isEnabled
                } else {
                    let newConnection = ConnectedRepository(
                        ownerID: ownerID, repositoryID: repo.id, installationID: repo.installationID,
                        fullName: repo.fullName, url: repo.url, isPrivate: repo.isPrivate, project: project)
                    newConnection.isEnabled = repo.isEnabled
                    context.insert(newConnection)
                }
            }
            for connection in connections where connection.ownerID == ownerID {
                if !journal.repositories.contains(where: { $0.id == connection.repositoryID }) {
                    connection.isEnabled = false
                }
            }
            for evidence in journal.evidence {
                let source =
                    sources.first { $0.identity == evidence.id }
                    ?? SourceActivity(
                        provider: "github", repositoryID: evidence.repositoryID, externalID: evidence.externalID,
                        kind: evidence.kind, title: evidence.title, url: evidence.url, occurredAt: evidence.occurredAt)
                if source.modelContext == nil { context.insert(source) }
                source.title = evidence.title
                source.url = evidence.url
                source.occurredAt = evidence.occurredAt
            }
            let incoming = Set(journal.entries.map(\.id))
            for entry in allEntries where entry.ownerID == ownerID && entry.generationID == generation.id {
                if entry.origin == .generated && !incoming.contains(entry.id) && !suppressed.contains(entry.id) {
                    context.delete(entry)
                }
            }
            for remote in journal.entries where !suppressed.contains(remote.id) {
                let entry =
                    allEntries.first { $0.remoteID == remote.id }
                    ?? BuildEntry(
                        id: remote.id, title: remote.title, kind: remote.kind, occurredAt: remote.occurredAt,
                        project: projectMap[remote.repositoryID], origin: .generated)
                if entry.origin == .userEditedGenerated { continue }
                if entry.modelContext == nil { context.insert(entry) }
                entry.remoteID = remote.id
                entry.ownerID = ownerID
                entry.localDay = journal.day
                entry.generationID = generation.id
                entry.title = remote.title
                entry.detail = remote.detail
                entry.kindRawValue = remote.kind.rawValue
                entry.occurredAt = remote.occurredAt
                entry.updatedAt = generation.generatedAt
                entry.confidence = remote.confidence
                entry.evidenceIDs = remote.evidenceIDs
                entry.originRawValue = (remote.userEdited ? EntryOrigin.userEditedGenerated : .generated).rawValue
            }
            if let narrative = journal.narrative, !suppressed.contains(narrative.id) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: journal.timeZone) ?? .current
                let parts = journal.day.split(separator: "-").compactMap { Int($0) }
                let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
                let key = JournalLogic.reflectionKey(for: start, calendar: calendar)
                let summary = try context.fetch(
                    FetchDescriptor<JournalSummary>(predicate: #Predicate { $0.key == key })
                ).first
                if summary == nil || summary?.originRawValue == SummaryOrigin.generatedDraft.rawValue {
                    if narrative.text.isEmpty {
                        if let summary { context.delete(summary) }
                    } else {
                        let value =
                            summary
                            ?? JournalSummary(
                                key: key, period: .daily, startDate: start,
                                endDate: calendar.date(byAdding: .day, value: 1, to: start)!, text: narrative.text,
                                origin: .generatedDraft)
                        if value.modelContext == nil { context.insert(value) }
                        value.text = narrative.text
                        value.originRawValue =
                            (narrative.userEdited ? SummaryOrigin.userEditedGenerated : .generatedDraft).rawValue
                        value.remoteID = narrative.id
                        value.ownerID = ownerID
                        value.evidenceIDs = narrative.evidenceIDs
                        value.inputEntryIDs = journal.entries.filter {
                            !$0.evidenceIDs.filter(narrative.evidenceIDs.contains).isEmpty
                        }.map(\.id)
                        value.updatedAt = generation.generatedAt
                    }
                }
            }
            let id = generation.id
            let run = try context.fetch(FetchDescriptor<GenerationRun>(predicate: #Predicate { $0.id == id })).first
            if let run {
                run.evidenceHash = generation.evidenceHash
                run.promptVersion = generation.promptVersion
                run.generatedAt = generation.generatedAt
            } else {
                context.insert(
                    GenerationRun(
                        id: id, ownerID: ownerID, localDay: journal.day, timeZone: journal.timeZone,
                        evidenceHash: generation.evidenceHash, promptVersion: generation.promptVersion,
                        generatedAt: generation.generatedAt))
            }
            let key = "\(ownerID):\(journal.day):\(journal.timeZone)"
            let checkpoint = try context.fetch(FetchDescriptor<SyncCheckpoint>(predicate: #Predicate { $0.key == key }))
                .first
            if let checkpoint {
                checkpoint.syncedAt = .now
                checkpoint.evidenceHash = generation.evidenceHash
            } else {
                context.insert(SyncCheckpoint(key: key, syncedAt: .now, evidenceHash: generation.evidenceHash))
            }
            try JournalStore.save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    static func validate(_ journal: AgentJournal, ownerID: String) throws {
        guard journal.userID == ownerID, TimeZone(identifier: journal.timeZone) != nil,
            journal.repositories.count <= 100, journal.entries.count <= 100, journal.evidence.count <= 200,
            Set(journal.repositories.map(\.id)).count == journal.repositories.count,
            Set(journal.entries.map(\.id)).count == journal.entries.count,
            Set(journal.evidence.map(\.id)).count == journal.evidence.count,
            journal.day.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
        else { throw AgentError.invalidResponse }
        let parts = journal.day.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: journal.timeZone)!
        guard parts.count == 3,
            let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
            AgentDay(date: date, timeZone: calendar.timeZone).day == journal.day
        else { throw AgentError.invalidResponse }
        let repos = Set(journal.repositories.map(\.id))
        let sources = Dictionary(uniqueKeysWithValues: journal.evidence.map { ($0.id, $0) })
        for repo in journal.repositories {
            guard URL(string: repo.url)?.scheme == "https", URL(string: repo.url)?.host == "github.com" else {
                throw AgentError.invalidResponse
            }
        }
        for source in journal.evidence {
            guard repos.contains(source.repositoryID),
                source.id
                    == EvidenceIdentity.make(
                        provider: "github", repositoryID: source.repositoryID,
                        kind: source.kind, externalID: source.externalID), URL(string: source.url)?.scheme == "https",
                URL(string: source.url)?.host == "github.com"
            else { throw AgentError.invalidResponse }
        }
        for entry in journal.entries {
            guard repos.contains(entry.repositoryID), !entry.title.isEmpty, entry.title.count <= 240,
                entry.detail.count <= 20_000, entry.confidence.isFinite, (0...1).contains(entry.confidence),
                !entry.evidenceIDs.isEmpty, Set(entry.evidenceIDs).count == entry.evidenceIDs.count,
                entry.evidenceIDs.allSatisfy({ sources[$0]?.repositoryID == entry.repositoryID })
            else { throw AgentError.invalidResponse }
        }
        if let narrative = journal.narrative {
            guard narrative.text.count <= 20_000, narrative.evidenceIDs.allSatisfy({ sources[$0] != nil }) else {
                throw AgentError.invalidResponse
            }
        }
    }

    static func enqueue(_ edit: JournalEdit, ownerID: String, context: ModelContext) throws {
        context.insert(
            JournalMutation(
                id: edit.mutationID, ownerID: ownerID, targetID: edit.targetID,
                targetType: edit.targetType, payload: try AgentCoding.encoder().encode(edit)))
    }

    static func evidence(for entry: BuildEntry, context: ModelContext) throws -> [SourceActivity] {
        let ids = Set(entry.evidenceIDs)
        let remote = try context.fetch(FetchDescriptor<SourceActivity>()).filter { ids.contains($0.identity) }
        return (entry.sources + remote).reduce(into: [String: SourceActivity]()) { $0[$1.identity] = $1 }
            .values.sorted { $0.occurredAt < $1.occurredAt }
    }
}
