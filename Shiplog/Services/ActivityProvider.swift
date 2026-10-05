import Foundation

/// Adapters normalize remote API payloads before they reach the journal.
/// A source event is evidence, not automatically a meaningful build entry.
struct RepositoryDescriptor: Identifiable, Codable, Sendable {
    let id: String
    let provider: String
    let name: String
    let url: URL?
}

struct ActivityEvidence: Identifiable, Codable, Sendable {
    let id: String
    let repositoryID: String
    let kind: Kind
    let title: String
    let occurredAt: Date
    let url: URL?

    enum Kind: String, Codable, Sendable {
        case commit, pullRequest, issue, release
    }
}

struct ActivityPage: Sendable {
    let activities: [ActivityEvidence]
    let nextCursor: String?
}

protocol ActivityProvider: Sendable {
    var identifier: String { get }
    func repositories() async throws -> [RepositoryDescriptor]
    func activity(repositoryID: String, interval: DateInterval, cursor: String?) async throws -> ActivityPage
}

struct SummaryInput: Sendable {
    let period: SummaryPeriod
    let interval: DateInterval
    let entries: [EntryRecord]
}

struct SummaryDraft: Sendable {
    let text: String
    let inputEntryIDs: [UUID]
    let generatedAt: Date
}

/// Generated content must remain a reviewable draft with input provenance.
protocol SummaryService: Sendable {
    func draft(for input: SummaryInput) async throws -> SummaryDraft
}
