//
//  JiraModels.swift
//  Toolbelt
//
//  Jira settings, the API responses and the arithmetic around them. Pure logic, no SwiftUI.
//

import Foundation

/// Cloud signs in with an email and an API token, Data Center with a personal access token.
enum JiraDeployment: String, CaseIterable, Identifiable {
    case cloud
    case dataCenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloud: return "Cloud"
        case .dataCenter: return "Data Center"
        }
    }
}

struct JiraCredentials: Hashable {
    var site = ""
    var email = ""
    var token = ""
    var deployment: JiraDeployment = .cloud

    var siteURL: URL? { JiraSite.url(from: site) }
    var needsEmail: Bool { deployment == .cloud }

    var problem: JiraError? {
        if site.isEmpty { return .missingSite }
        if siteURL == nil { return .invalidSite }
        if needsEmail && email.isEmpty { return .missingEmail }
        if token.isEmpty { return .missingToken }
        return nil
    }

    var isConfigured: Bool { problem == nil }

    var authorization: String {
        switch deployment {
        case .cloud: return "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
        case .dataCenter: return "Bearer \(token)"
        }
    }

    func trimmed() -> JiraCredentials {
        JiraCredentials(
            site: site.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            deployment: deployment
        )
    }
}

enum JiraSite {
    private static let pageSegments: Set<String> = ["browse", "secure", "projects", "issues", "plugins", "rest"]

    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// A pasted issue or board link still means the site. On Atlassian Cloud the API is at the root;
    /// elsewhere the path up to the first page is the context path, such as `/jira`.
    /// The token travels in a header, so plain http is allowed for a local Jira only.
    static func url(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              scheme == "https" || (scheme == "http" && localHosts.contains(host))
        else { return nil }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        if host.hasSuffix(".atlassian.net") {
            components.path = ""
        } else {
            let contextPath = components.path
                .split(separator: "/")
                .map(String.init)
                .prefix { !pageSegments.contains($0.lowercased()) && !$0.contains(".") }
            components.path = contextPath.isEmpty ? "" : "/" + contextPath.joined(separator: "/")
        }
        return components.url
    }

    static func apiURL(_ site: URL, path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: site, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/rest/api/2" + path
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }
}

struct JiraUser: Decodable, Hashable {
    let accountId: String?
    let key: String?
    let name: String?

    var isIdentified: Bool { accountId != nil || key != nil || name != nil }

    /// Cloud identifies people by `accountId`, Data Center by `key`, old servers only by `name`.
    func isSamePerson(as other: JiraUser) -> Bool {
        if let accountId, let otherID = other.accountId { return accountId == otherID }
        if let key, let otherKey = other.key { return key == otherKey }
        if let name, let otherName = other.name { return name == otherName }
        return false
    }
}

struct JiraIssueRef: Hashable {
    let key: String
    let summary: String
}

/// Cloud pages with `nextPageToken`, Data Center with `startAt` and `total`.
struct JiraSearchPage: Decodable {
    struct Issue: Decodable {
        struct Fields: Decodable {
            let summary: String?
        }

        let id: String?
        let key: String?
        let fields: Fields?
    }

    let issues: [Issue]
    let nextPageToken: String?
    let isLast: Bool?
    let total: Int?

    var issueRefs: [JiraIssueRef] {
        issues.compactMap { issue in
            guard let key = issue.key ?? issue.id else { return nil }
            return JiraIssueRef(key: key, summary: issue.fields?.summary ?? key)
        }
    }
}

struct JiraWorklogPage: Decodable {
    struct Entry: Decodable {
        let id: String
        let author: JiraUser?
        let comment: String?
        let started: String
        let timeSpentSeconds: Int?

        private enum CodingKeys: String, CodingKey {
            case id, author, comment, started, timeSpentSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            author = try container.decodeIfPresent(JiraUser.self, forKey: .author)
            // API v3 sends a rich-text document here; a comment is not worth failing the page over.
            comment = try? container.decodeIfPresent(String.self, forKey: .comment)
            started = try container.decode(String.self, forKey: .started)
            timeSpentSeconds = try container.decodeIfPresent(Int.self, forKey: .timeSpentSeconds)
        }
    }

    let total: Int?
    let worklogs: [Entry]
}

enum JiraWorklog {
    /// `worklogDate` is a day in the Jira profile's time zone, which may differ from the Mac's,
    /// so the query takes a day more on each side and `entries` cuts the exact week.
    static func jql(from: Date, to: Date, calendar: Calendar = AppFormatters.calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let first = calendar.date(byAdding: .day, value: -1, to: from) ?? from
        let last = calendar.date(byAdding: .day, value: 1, to: to) ?? to
        return "worklogAuthor = currentUser()"
            + " AND worklogDate >= \"\(formatter.string(from: first))\""
            + " AND worklogDate < \"\(formatter.string(from: last))\""
    }

    static func entries(
        _ entries: [JiraWorklogPage.Entry],
        issue: JiraIssueRef,
        author: JiraUser,
        from: Date,
        to: Date
    ) -> [Worklog] {
        entries.compactMap { entry in
            guard let entryAuthor = entry.author, entryAuthor.isSamePerson(as: author),
                  let id = Int(entry.id),
                  let start = TrackerDate.parse(entry.started),
                  start >= from, start < to
            else { return nil }

            return Worklog(
                id: id,
                issueKey: issue.key,
                issueTitle: issue.summary,
                comment: entry.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                seconds: TimeInterval(entry.timeSpentSeconds ?? 0)
            )
        }
    }
}
