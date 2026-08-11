//
//  TrackerClient.swift
//  Toolbelt
//
//  Сетевой слой Яндекс Трекера.
//

import Foundation
import OSLog

protocol TrackerService {
    func worklog(from: Date, to: Date) async throws -> [Worklog]
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

// MARK: - Клиент

@MainActor
final class TrackerClient: TrackerService {
    private enum Limits {
        static let worklogPageSize = 1000
        static let issuesPageSize = 200
        static let requestTimeout: TimeInterval = 60
        /// Запись можно залогировать задним числом, поэтому окно по `createdAt` шире недели.
        static let createdAtPaddingDays = 30
    }

    private let baseURL = URL(string: "https://api.tracker.yandex.net/v3")
    private let session: URLSession
    private let credentialsProvider: TrackerCredentialsProviding

    /// Логин не меняется в пределах токена, а нужен для каждого запроса worklog.
    private var cachedLogin: (token: String, login: String)?

    init(
        session: URLSession = .shared,
        credentialsProvider: TrackerCredentialsProviding = TrackerCredentialsStore.shared
    ) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    // MARK: Публичный API

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
            path: "/worklog/_search",
            query: [URLQueryItem(name: "perPage", value: String(Limits.worklogPageSize))],
            payload: payload
        )
        let raw: [WorklogDTO] = try decode(data)

        if raw.count >= Limits.worklogPageSize {
            Log.tracker.warning("Достигнут предел страницы worklog — часть записей могла не попасть в отчёт")
        }

        return raw
            .compactMap { dto -> Worklog? in
                guard let start = TrackerDate.parse(dto.start) else {
                    Log.tracker.warning("Запись пропущена: не разобрана дата")
                    return nil
                }
                guard start >= from, start < to else { return nil }

                return Worklog(
                    id: dto.id,
                    issueKey: dto.issue.key,
                    issueTitle: dto.issue.display ?? dto.issue.key,
                    comment: dto.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: start,
                    seconds: TrackerDuration.seconds(fromISO8601: dto.duration)
                )
            }
            .sorted { $0.start < $1.start }
    }

    func myIssues(includeResolved: Bool) async throws -> [Issue] {
        var parts = ["Assignee: me()"]
        if !includeResolved {
            parts.append("Resolution: empty()")
        }
        parts.append("\"Sort by\": Updated DESC")

        let data = try await send(
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
                statusName: dto.status?.display ?? "Без статуса",
                priorityKey: dto.priority?.key ?? "normal",
                priorityName: dto.priority?.display ?? "",
                queueName: dto.queue?.display ?? dto.queue?.key ?? "",
                updatedAt: dto.updatedAt.flatMap(TrackerDate.parse),
                deadline: dto.deadline.flatMap(TrackerDate.parse)
            )
        }
    }

    // MARK: Транспорт

    private func currentLogin() async throws -> String {
        let token = credentialsProvider.credentials.token
        if let cachedLogin, cachedLogin.token == token {
            return cachedLogin.login
        }

        let data = try await send(path: "/myself", query: [], payload: nil)
        let myself: TrackerMyselfDTO = try decode(data)

        guard let login = myself.login?.nonEmpty ?? myself.uid.map(String.init) else {
            throw TrackerError.unknownUser
        }

        cachedLogin = (token, login)
        return login
    }

    private func send(path: String, query: [URLQueryItem], payload: [String: Any]?) async throws -> Data {
        let request = try makeRequest(path: path, query: query, payload: payload)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TrackerError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            Log.tracker.error("HTTP \(http.statusCode, privacy: .public) на \(path, privacy: .public)")
            throw TrackerError.from(status: http.statusCode, body: body)
        }
        return data
    }

    private func makeRequest(path: String, query: [URLQueryItem], payload: [String: Any]?) throws -> URLRequest {
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
        request.httpMethod = payload == nil ? "GET" : "POST"
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
