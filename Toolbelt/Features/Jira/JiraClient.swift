//
//  JiraClient.swift
//  Toolbelt
//
//  The Jira network layer. API v2 answers the same on Cloud and Data Center,
//  except for search.
//

import Foundation
import OSLog

@MainActor
final class JiraClient: WorklogService {
    private enum Limits {
        static let searchPageSize = 100
        static let searchPageLimit = 20
        static let worklogPageSize = 1000
        static let concurrentIssues = 6
        static let requestTimeout: TimeInterval = 60
        static let day: TimeInterval = 24 * 3600
    }

    private let session: URLSession
    private let credentialsProvider: JiraCredentialsProviding

    private var cachedUser: (credentials: JiraCredentials, user: JiraUser)?

    convenience init() {
        self.init(session: .shared, credentialsProvider: JiraCredentialsStore.shared)
    }

    init(session: URLSession, credentialsProvider: JiraCredentialsProviding) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    // MARK: Public API

    var isConfigured: Bool { credentialsProvider.credentials.isConfigured }
    var settingsRevision: AnyHashable { AnyHashable(credentialsProvider.credentials) }

    func worklog(from: Date, to: Date) async throws -> [Worklog] {
        let credentials = try validCredentials()
        let user = try await currentUser(credentials)
        let issues = try await issuesWithWorklog(from: from, to: to, credentials: credentials)

        let load: @Sendable (JiraIssueRef) async throws -> [Worklog] = { issue in
            try await self.worklog(of: issue, author: user, from: from, to: to, credentials: credentials)
        }

        let entries = try await withThrowingTaskGroup(of: [Worklog].self, returning: [Worklog].self) { group in
            var pending = issues.makeIterator()
            for _ in 0..<Limits.concurrentIssues {
                guard let issue = pending.next() else { break }
                group.addTask { try await load(issue) }
            }

            var entries: [Worklog] = []
            while let batch = try await group.next() {
                entries += batch
                if let issue = pending.next() {
                    group.addTask { try await load(issue) }
                }
            }
            return entries
        }
        return entries.sorted { $0.start < $1.start }
    }

    // MARK: Requests

    private func validCredentials() throws -> JiraCredentials {
        let credentials = credentialsProvider.credentials
        guard !credentials.site.isEmpty else { throw JiraError.missingSite }
        guard credentials.siteURL != nil else { throw JiraError.invalidURL }
        guard !credentials.needsEmail || !credentials.email.isEmpty else { throw JiraError.missingEmail }
        guard !credentials.token.isEmpty else { throw JiraError.missingToken }
        return credentials
    }

    private func currentUser(_ credentials: JiraCredentials) async throws -> JiraUser {
        if let cachedUser, cachedUser.credentials == credentials {
            return cachedUser.user
        }

        let user: JiraUser = try await send("/myself", credentials: credentials)
        guard user.isIdentified else { throw JiraError.unknownUser }

        cachedUser = (credentials, user)
        return user
    }

    private func issuesWithWorklog(from: Date, to: Date, credentials: JiraCredentials) async throws -> [JiraIssueRef] {
        var payload: [String: Any] = [
            "jql": JiraWorklog.jql(from: from, to: to),
            "fields": ["summary"],
            "maxResults": Limits.searchPageSize
        ]
        var issues: [JiraIssueRef] = []
        var startAt = 0
        var seenTokens: Set<String> = []

        for _ in 0..<Limits.searchPageLimit {
            switch credentials.deployment {
            case .cloud:
                let page: JiraSearchPage = try await send("/search/jql", payload: payload, credentials: credentials)
                issues += page.issueRefs
                // Cloud has been seen to hand out the same token forever instead of ending the list.
                guard page.isLast != true,
                      let token = page.nextPageToken,
                      seenTokens.insert(token).inserted
                else { return unique(issues) }
                payload["nextPageToken"] = token

            case .dataCenter:
                payload["startAt"] = startAt
                let page: JiraSearchPage = try await send("/search", payload: payload, credentials: credentials)
                issues += page.issueRefs
                startAt += page.issues.count
                guard !page.issues.isEmpty, startAt < (page.total ?? 0) else { return unique(issues) }
            }
        }

        Log.jira.warning("Search page limit reached — some issues may be missing from the report")
        return unique(issues)
    }

    private func worklog(
        of issue: JiraIssueRef,
        author: JiraUser,
        from: Date,
        to: Date,
        credentials: JiraCredentials
    ) async throws -> [Worklog] {
        // Loose bounds: Data Center ignores them, and the exact week is cut out afterwards.
        let after = milliseconds(from.addingTimeInterval(-Limits.day))
        let before = milliseconds(to.addingTimeInterval(Limits.day))

        var entries: [JiraWorklogPage.Entry] = []
        while true {
            let page: JiraWorklogPage = try await send(
                "/issue/\(issue.key)/worklog",
                query: [
                    URLQueryItem(name: "startAt", value: String(entries.count)),
                    URLQueryItem(name: "maxResults", value: String(Limits.worklogPageSize)),
                    URLQueryItem(name: "startedAfter", value: String(after)),
                    URLQueryItem(name: "startedBefore", value: String(before))
                ],
                credentials: credentials
            )
            entries += page.worklogs
            guard !page.worklogs.isEmpty, entries.count < (page.total ?? 0) else { break }
        }

        return JiraWorklog.entries(entries, issue: issue, author: author, from: from, to: to)
    }

    // MARK: Transport

    private func send<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        payload: [String: Any]? = nil,
        credentials: JiraCredentials
    ) async throws -> T {
        let request = try makeRequest(path: path, query: query, payload: payload, credentials: credentials)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw JiraError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            Log.jira.error("HTTP \(http.statusCode, privacy: .public) on \(path, privacy: .public)")
            throw JiraError.from(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JiraError.decoding(error.localizedDescription)
        }
    }

    private func makeRequest(
        path: String,
        query: [URLQueryItem],
        payload: [String: Any]?,
        credentials: JiraCredentials
    ) throws -> URLRequest {
        guard let site = credentials.siteURL,
              let url = JiraSite.apiURL(site, path: path, query: query)
        else { throw JiraError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.timeoutInterval = Limits.requestTimeout
        request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        return request
    }

    private func unique(_ issues: [JiraIssueRef]) -> [JiraIssueRef] {
        var seen: Set<String> = []
        return issues.filter { seen.insert($0.key).inserted }
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
