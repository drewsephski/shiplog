import Foundation

struct AgentClient: Sendable {
    let baseURL: URL
    var transport: URLSession = URLSession(
        configuration: .ephemeral, delegate: AgentRedirectPolicy(), delegateQueue: nil)

    struct ConnectionStart: Codable, Sendable { let url: URL }
    struct Acknowledgment: Codable, Sendable { let ok: Bool }
    struct AcceptedEdits: Codable, Sendable { let accepted: [UUID] }
    struct Account: Codable, Sendable {
        let userID: String
        let login: String
        let timeZone: String
        let finalizeMinute: Int
        let includePatches: Bool
    }
    struct HistoryPage: Codable, Sendable {
        let journals: [AgentJournal]
        let nextCursor: String?
        let syncedThrough: Date
    }
    func history(session: AgentSession, since: Date?, cursor: String?) async throws -> HistoryPage {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/journals"), resolvingAgainstBaseURL: false)
        if let cursor {
            components?.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        } else if let since {
            components?.queryItems = [URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since))]
        }
        guard let url = components?.url else { throw AgentError.invalidResponse }
        return try await send(url: url, method: "GET", session: session, data: nil)
    }
    private struct ErrorResponse: Decodable { let error: String }

    func start(challenge: String, timeZone: String) async throws -> ConnectionStart {
        try await request("api/connect/start", body: ["challenge": challenge, "timeZone": timeZone])
    }
    func exchange(code: String, verifier: String) async throws -> AgentSession {
        try await request("api/connect/exchange", body: ["code": code, "verifier": verifier])
    }
    func journal(session: AgentSession, day: AgentDay, generate: Bool) async throws -> AgentJournal {
        if generate { return try await request("api/sync", session: session, body: day) }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/journal"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "day", value: day.day), URLQueryItem(name: "timeZone", value: day.timeZone),
        ]
        guard let url = components?.url else { throw AgentError.invalidResponse }
        return try await send(url: url, method: "GET", session: session, data: nil)
    }
    func edits(session: AgentSession, edits: [JournalEdit]) async throws -> AcceptedEdits {
        struct Input: Encodable, Sendable { let edits: [JournalEdit] }
        return try await request("api/journal/edits", session: session, body: Input(edits: edits))
    }
    func account(session: AgentSession) async throws -> Account {
        try await send(url: baseURL.appendingPathComponent("api/account"), method: "GET", session: session, data: nil)
    }
    func settings(session: AgentSession, timeZone: String, minute: Int) async throws -> Acknowledgment {
        struct Input: Encodable, Sendable {
            let timeZone: String
            let finalizeMinute: Int
        }
        return try await request(
            "api/account", method: "PATCH", session: session, body: Input(timeZone: timeZone, finalizeMinute: minute))
    }
    func disconnect(session: AgentSession, deleteData: Bool) async throws -> Acknowledgment {
        try await send(
            url: baseURL.appendingPathComponent(deleteData ? "api/account" : "api/connection"), method: "DELETE",
            session: session, data: nil)
    }
    private func request<Output: Decodable & Sendable, Input: Encodable & Sendable>(
        _ path: String, method: String = "POST", session: AgentSession? = nil, body: Input
    ) async throws -> Output {
        try await send(
            url: baseURL.appendingPathComponent(path), method: method, session: session,
            data: AgentCoding.encoder().encode(body))
    }
    private func send<Output: Decodable & Sendable>(url: URL, method: String, session: AgentSession?, data: Data?)
        async throws -> Output
    {
        guard url.scheme == "https", url.host == baseURL.host else { throw AgentError.notConfigured }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        request.httpMethod = method
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session { request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization") }
        let (body, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, body.count <= 2_000_000 else {
            throw AgentError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: body))?.error
            throw AgentError.failed(message ?? "Shiplog couldn’t connect. Check your connection and try again.")
        }
        return try AgentCoding.decoder().decode(Output.self, from: body)
    }
}

/// Keep the bearer token and journal edits on the configured agent origin.
private final class AgentRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
