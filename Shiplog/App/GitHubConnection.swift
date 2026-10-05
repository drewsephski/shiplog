import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftData
import UIKit

/// Shared connection state, not a screen view model. The server owns the agent.
@MainActor @Observable final class GitHubConnection: NSObject {
    private(set) var session: AgentSession?
    private(set) var isBusy = false
    private(set) var status = ""
    var errorMessage: String?
    private var browser: ASWebAuthenticationSession?
    private var operationID = UUID()
    private let client: AgentClient?

    override init() {
        if let value = Bundle.main.object(forInfoDictionaryKey: "ShiplogAgentURL") as? String,
            let url = URL(string: value), url.scheme == "https", url.host != nil, url.path.isEmpty || url.path == "/"
        { client = AgentClient(baseURL: url) } else { client = nil }
        super.init()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--preview-data") { return }
        #endif
        do { session = try SessionKeychain.read() } catch { errorMessage = error.localizedDescription }
    }

    var isConnected: Bool { session != nil }
    var isConfigured: Bool { client != nil }

    func connect(context: ModelContext) async {
        guard !isBusy else { return }
        guard let client else { errorMessage = AgentError.notConfigured.localizedDescription; return }
        isBusy = true
        errorMessage = nil
        status = "Connecting GitHub…"
        defer { isBusy = false }
        do {
            let verifier = try secureToken()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
            let start = try await client.start(challenge: challenge, timeZone: TimeZone.current.identifier)
            guard start.url.scheme == "https", start.url.host == client.baseURL.host else { throw AgentError.invalidResponse }
            let callback = try await authorize(url: start.url)
            let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            guard callback.scheme == "shiplog", callback.host == "github-connected",
                let code = parts?.queryItems?.first(where: { $0.name == "code" })?.value else { throw AgentError.invalidResponse }
            let connected = try await client.exchange(code: code, verifier: verifier)
            try SessionKeychain.write(connected)
            session = connected
            status = "Analyzing today…"
            try await synchronize(context: context, session: connected, generate: true)
        } catch is CancellationError {
            status = ""
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = ""
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(context: ModelContext, generate: Bool = false) async {
        guard !isBusy, let session else { return }
        isBusy = true
        errorMessage = nil
        status = generate ? "Analyzing today…" : "Refreshing your journal…"
        defer { isBusy = false }
        do { try await synchronize(context: context, session: session, generate: generate) }
        catch is CancellationError { status = "" }
        catch { errorMessage = error.localizedDescription }
    }

    private func synchronize(context: ModelContext, session: AgentSession, generate: Bool) async throws {
        guard let client else { throw AgentError.notConfigured }
        let operation = operationID
        let pending = try context.fetch(FetchDescriptor<JournalMutation>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { $0.ownerID == session.userID }
        for offset in stride(from: 0, to: pending.count, by: 50) {
            let batch = Array(pending[offset..<min(offset + 50, pending.count)])
            let edits = try batch.map { try AgentCoding.decoder().decode(JournalEdit.self, from: $0.payload) }
            let ack = try await client.edits(session: session, edits: edits)
            guard operationID == operation else { throw CancellationError() }
            let accepted = Set(ack.accepted)
            for mutation in batch where accepted.contains(mutation.id) { context.delete(mutation) }
            try JournalStore.save(context)
        }
        let day = AgentDay()
        var journal = try await client.journal(session: session, day: day, generate: generate)
        guard operationID == operation else { throw CancellationError() }
        if journal.generation == nil && journal.status == "idle" && !generate {
            status = "Analyzing today…"
            journal = try await client.journal(session: session, day: day, generate: true)
        }
        guard journal.day == day.day, journal.timeZone == day.timeZone, operationID == operation else { throw AgentError.invalidResponse }
        try JournalSyncStore.merge(journal, ownerID: session.userID, context: context)
        switch journal.status {
        case "running", "pending": status = "Analyzing today… You can leave Shiplog open or come back later."
        case "failed": throw AgentError.failed("Today’s analysis needs another try. Check GitHub access, then tap Analyze today.")
        default: status = journal.entries.isEmpty ? "No attributable activity found for today." : "Your journal is up to date."
        }
    }

    func updateSchedule(minute: Int) async {
        guard !isBusy, let client, var value = session else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.settings(session: value, timeZone: TimeZone.current.identifier, minute: minute)
            guard response.ok else { throw AgentError.invalidResponse }
            value.finalizeMinute = minute
            value.timeZone = TimeZone.current.identifier
            try SessionKeychain.write(value)
            session = value
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect(deleteData: Bool, context: ModelContext) async {
        guard !isBusy, let session, let client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.disconnect(session: session, deleteData: deleteData)
            guard response.ok else { throw AgentError.invalidResponse }
            operationID = UUID()
            try SessionKeychain.delete()
            self.session = nil
            status = ""
            for repo in try context.fetch(FetchDescriptor<ConnectedRepository>()) where repo.ownerID == session.userID {
                repo.isEnabled = false
            }
            if deleteData {
                for entry in try context.fetch(FetchDescriptor<BuildEntry>()) where entry.ownerID == session.userID {
                    entry.remoteID = nil
                    entry.ownerID = nil
                }
                for summary in try context.fetch(FetchDescriptor<JournalSummary>()) where summary.ownerID == session.userID {
                    summary.remoteID = nil
                    summary.ownerID = nil
                }
                for mutation in try context.fetch(FetchDescriptor<JournalMutation>()) where mutation.ownerID == session.userID {
                    context.delete(mutation)
                }
            }
            try JournalStore.save(context)
        } catch { errorMessage = error.localizedDescription }
    }

    private func authorize(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let browser = ASWebAuthenticationSession(url: url, callbackURLScheme: "shiplog") { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? AgentError.invalidResponse) }
            }
            browser.presentationContextProvider = self
            browser.prefersEphemeralWebBrowserSession = true
            self.browser = browser
            if !browser.start() { continuation.resume(throwing: AgentError.failed("Couldn’t open GitHub sign-in. Please try again.")) }
        }
    }
    private func secureToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AgentError.credentialFailure }
        return Data(bytes).base64URLString
    }
}

extension GitHubConnection: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
private extension Data {
    var base64URLString: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

private enum SessionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.drewsepeczi.shiplog.agent", kSecAttrAccount as String: "github-session"]
    }
    static func read() throws -> AgentSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AgentError.credentialFailure }
        return try AgentCoding.decoder().decode(AgentSession.self, from: data)
    }
    static func write(_ value: AgentSession) throws {
        let data = try AgentCoding.encoder().encode(value)
        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(newItem as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess else { throw AgentError.credentialFailure }
        } else if status != errSecSuccess { throw AgentError.credentialFailure }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AgentError.credentialFailure }
    }
}
