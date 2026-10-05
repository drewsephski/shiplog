import Foundation

enum EvidenceIdentity {
    static func make(provider: String, repositoryID: String, kind: String, externalID: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return [provider, repositoryID, kind, externalID].map {
            $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0
        }.joined(separator: ":")
    }
}

struct AgentSession: Codable, Sendable {
    let token: String
    let userID: String
    let login: String
    var timeZone: String
    var finalizeMinute: Int
    let includePatches: Bool
}

struct AgentDay: Codable, Sendable {
    let day: String
    let timeZone: String
    init(date: Date = .now, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        self.timeZone = timeZone.identifier
    }
}

struct AgentJournal: Codable, Sendable {
    let userID: String
    let day: String
    let timeZone: String
    let status: String
    let errorCode: String?
    let repositories: [Repository]
    let entries: [Entry]
    let evidence: [Evidence]
    let narrative: Narrative?
    let generation: Generation?

    struct Repository: Codable, Sendable {
        let id: String
        let installationID: String
        let name: String
        let fullName: String
        let url: String
        let description: String
        let isPrivate: Bool
        let isEnabled: Bool
        let defaultBranch: String
        let checkpoint: Date?
    }
    struct Entry: Codable, Sendable {
        let id: UUID
        let repositoryID: String
        let title: String
        let detail: String
        let kind: BuildKind
        let confidence: Double
        let evidenceIDs: [String]
        let occurredAt: Date
        let userEdited: Bool
        let userDeleted: Bool
    }
    struct Evidence: Codable, Sendable {
        let id: String
        let repositoryID: String
        let externalID: String
        let kind: String
        let title: String
        let occurredAt: Date
        let url: String
        let actorID: String
    }
    struct Narrative: Codable, Sendable {
        let id: UUID
        let text: String
        let userEdited: Bool
        let evidenceIDs: [String]
    }
    struct Generation: Codable, Sendable {
        let id: UUID
        let evidenceHash: String
        let promptVersion: String
        let generatedAt: Date
    }
}

struct JournalEdit: Codable, Sendable {
    let mutationID: UUID
    let targetID: UUID
    let targetType: String
    let deleted: Bool
    let title: String?
    let detail: String?
    let kind: BuildKind?
    let occurredAt: Date?
}

enum AgentError: LocalizedError {
    case notConfigured, invalidResponse, failed(String), credentialFailure
    var errorDescription: String? {
        switch self {
        case .notConfigured: "GitHub connection needs a configured Shiplog agent in this build. You can keep a journal manually meanwhile."
        case .invalidResponse: "The agent returned an invalid journal. Your saved journal hasn’t changed."
        case .failed(let message): message
        case .credentialFailure: "Your secure connection couldn’t be saved or opened. Please try connecting again."
        }
    }
}

enum AgentCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let text = try value.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw AgentError.invalidResponse
            }
            return date
        }
        return decoder
    }
}
