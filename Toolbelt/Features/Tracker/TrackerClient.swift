//
//  TrackerClient.swift
//  Toolbelt
//
//  The Yandex Tracker network layer.
//

import Foundation
import OSLog

protocol TrackerService: WorklogService {
    func myIssues(includeResolved: Bool) async throws -> [Issue]
}

// MARK: - DTO

private struct TrackerMyselfDTO: Decodable {
    let uid: Int?
    let login: String?
}

private struct WorklogDTO: Decodable {
    struct IssueRef: Decodable {
        let key: String
        let display: String?
    }

    let id: Int
    let issue: IssueRef
    let comment: String?
    let start: String
    let duration: String
}

private struct IssueDTO: Decodable {
    struct Ref: Decodable {
        let key: String?
        let display: String?
    }

    let key: String
    let summary: String
    let status: Ref?
    let priority: Ref?
    let queue: Ref?
    let updatedAt: String?
    let deadline: String?
}

private extension Worklog {
    init?(_ dto: WorklogDTO) {
        guard let start = TrackerDate.parse(dto.start) else { return nil }
        self.init(
            id: dto.id,
            issueKey: dto.issue.key,
            issueTitle: dto.issue.display ?? dto.issue.key,
            comment: dto.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
            start: start,
            seconds: TrackerDuration.seconds(fromISO8601: dto.duration)
        )
    }
}

// MARK: - Client

@MainActor
final class TrackerClient: TrackerService, WorklogEditing {
    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    private enum Limits {
        static let worklogPageSize = 1000
        static let issuesPageSize = 200
        static let requestTimeout: TimeInterval = 60
        /// An entry can be logged retroactively, so the `createdAt` window is wider than the week.
        static let createdAtPaddingDays = 30
    }

    private let baseURL = URL(string: "https://api.tracker.yandex.net/v3")
    private let session: URLSession
    private let credentialsProvider: TrackerCredentialsProviding

    /// The login does not change for a given token but is needed by every worklog request.
    private var cachedLogin: (token: String, login: String)?

    convenience init() {
        self.init(session: .shared, credentialsProvider: TrackerCredentialsStore.shared)
    }

    init(session: URLSession, credentialsProvider: TrackerCredentialsProviding) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    // MARK: Public API

    var isConfigured: Bool { credentialsProvider.credentials.isConfigured }
    var settingsRevision: AnyHashable { AnyHashable(credentialsProvider.credentials) }

    func worklog(from: Date, to: Date) async throws -> [Worklog] {
        let login = try await currentLogin()
        let calendar = AppFormatters.calendar
        let padding = Limits.createdAtPaddingDays
        let createdFrom = calendar.date(byAdding: .day, value: -padding, to: from) ?? from
        let createdTo = calendar.date(byAdding: .day, value: padding, to: to) ?? to

        let payload: [String: Any] = [
            "createdBy": login,
            "createdAt": [
                "from": TrackerDate.string(from: createdFrom),
                "to": TrackerDate.string(from: createdTo)
            ]
        ]

        let data = try await send(
            .post,
            path: "/worklog/_search",
            query: [URLQueryItem(name: "perPage", value: String(Limits.worklogPageSize))],
            payload: payload
        )
        let raw: [WorklogDTO] = try decode(data)

        if raw.count >= Limits.worklogPageSize {
            Log.tracker.warning("Worklog page limit reached — some entries may be missing from the report")
        }

        return raw
            .compactMap { dto -> Worklog? in
                guard let entry = Worklog(dto) else {
                    Log.tracker.warning("Entry skipped: could not parse its date")
                    return nil
                }
                return entry.start >= from && entry.start < to ? entry : nil
            }
            .sorted { $0.start < $1.start }
    }

    func updateComment(of entry: Worklog, to comment: String) async throws -> Worklog {
        let payload: [String: Any] = [
            // Tracker rejects the edit without a duration, even when only the comment changes.
            "duration": TrackerDuration.iso8601(seconds: entry.seconds),
            "comment": comment
        ]
        let data = try await send(.patch, path: worklogPath(of: entry), payload: payload)
        let dto: WorklogDTO = try decode(data)

        guard let updated = Worklog(dto) else {
            return entry.with(comment: comment)
        }
        return updated
    }

    func delete(_ entry: Worklog) async throws {
        do {
            _ = try await send(.delete, path: worklogPath(of: entry))
        } catch TrackerError.notFound {
            // Already deleted in Tracker itself — the outcome the user asked for.
        }
    }

    func myIssues(includeResolved: Bool) async throws -> [Issue] {
        var parts = ["Assignee: me()"]
        if !includeResolved {
            parts.append("Resolution: empty()")
        }
        parts.append("\"Sort by\": Updated DESC")

        let data = try await send(
            .post,
            path: "/issues/_search",
            query: [URLQueryItem(name: "perPage", value: String(Limits.issuesPageSize))],
            payload: ["query": parts.joined(separator: " ")]
        )
        let raw: [IssueDTO] = try decode(data)

        return raw.map { dto in
            Issue(
                key: dto.key,
                summary: dto.summary,
                statusKey: dto.status?.key ?? "unknown",
                statusName: dto.status?.display ?? "No status",
                priorityKey: dto.priority?.key ?? "normal",
                priorityName: dto.priority?.display ?? "",
                queueName: dto.queue?.display ?? dto.queue?.key ?? "",
                updatedAt: dto.updatedAt.flatMap(TrackerDate.parse),
                deadline: dto.deadline.flatMap(TrackerDate.parse)
            )
        }
    }

    // MARK: Transport

    private func currentLogin() async throws -> String {
        let token = credentialsProvider.credentials.token
        if let cachedLogin, cachedLogin.token == token {
            return cachedLogin.login
        }

        let data = try await send(.get, path: "/myself")
        let myself: TrackerMyselfDTO = try decode(data)

        guard let login = myself.login?.nonEmpty ?? myself.uid.map(String.init) else {
            throw TrackerError.unknownUser
        }

        cachedLogin = (token, login)
        return login
    }

    private func worklogPath(of entry: Worklog) -> String {
        "/issues/\(entry.issueKey)/worklog/\(entry.id)"
    }

    private func send(
        _ method: Method,
        path: String,
        query: [URLQueryItem] = [],
        payload: [String: Any]? = nil
    ) async throws -> Data {
        let request = try makeRequest(method: method, path: path, query: query, payload: payload)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TrackerError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            Log.tracker.error(
                "HTTP \(http.statusCode, privacy: .public) on \(method.rawValue, privacy: .public) \(path, privacy: .public)"
            )
            throw TrackerError.from(status: http.statusCode, body: body)
        }
        return data
    }

    private func makeRequest(
        method: Method,
        path: String,
        query: [URLQueryItem],
        payload: [String: Any]?
    ) throws -> URLRequest {
        let credentials = credentialsProvider.credentials
        guard !credentials.token.isEmpty else { throw TrackerError.missingToken }
        guard !credentials.orgId.isEmpty else { throw TrackerError.missingOrgId }

        guard let baseURL,
              var components = URLComponents(
                  url: baseURL.appendingPathComponent(path),
                  resolvingAgainstBaseURL: false
              )
        else { throw TrackerError.invalidURL }

        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw TrackerError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = Limits.requestTimeout
        request.setValue("OAuth \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.orgId, forHTTPHeaderField: credentials.orgKind.headerName)

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        return request
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TrackerError.decoding(error.localizedDescription)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
