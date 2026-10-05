import Foundation

enum JournalValidationError: LocalizedError, Equatable {
    case titleRequired, titleTooLong, projectRequired, projectNameRequired, projectNameTooLong
    case futureDate, invalidRepositoryURL, detailTooLong

    var errorDescription: String? {
        switch self {
        case .titleRequired: "Give this entry a title."
        case .titleTooLong: "Keep the title under 241 characters."
        case .projectRequired: "Choose a project for this entry."
        case .projectNameRequired: "Give your project a name."
        case .projectNameTooLong: "Keep the project name under 81 characters."
        case .futureDate: "Work can only be logged for today or an earlier date."
        case .invalidRepositoryURL:
            "Enter a complete HTTPS repository URL without credentials, query parameters, or fragments."
        case .detailTooLong: "Keep your notes under 20,001 characters."
        }
    }
}

enum JournalValidation {
    static func entry(title: String, detail: String, projectID: UUID?, date: Date, now: Date = .now) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JournalValidationError.titleRequired
        }
        guard title.count <= 240 else { throw JournalValidationError.titleTooLong }
        guard detail.count <= 20_000 else { throw JournalValidationError.detailTooLong }
        guard projectID != nil else { throw JournalValidationError.projectRequired }
        guard date <= now else { throw JournalValidationError.futureDate }
    }

    static func project(name: String, overview: String, repositoryURL: String) throws -> String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JournalValidationError.projectNameRequired
        }
        guard name.count <= 80 else { throw JournalValidationError.projectNameTooLong }
        guard overview.count <= 20_000 else { throw JournalValidationError.detailTooLong }
        let value = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard let url = URLComponents(string: value), url.scheme == "https",
            let host = url.host, host.contains("."), url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil
        else {
            throw JournalValidationError.invalidRepositoryURL
        }
        return value
    }
}
