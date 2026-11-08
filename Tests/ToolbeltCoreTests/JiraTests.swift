import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Jira site address")
struct JiraSiteTests {
    private func site(_ string: String) -> String? {
        JiraSite.url(from: string)?.absoluteString
    }

    @Test("A bare host gets https")
    func bareHostGetsHTTPS() {
        #expect(site("company.atlassian.net") == "https://company.atlassian.net")
        #expect(site("jira.company.com:8443/") == "https://jira.company.com:8443")
    }

    @Test("A Cloud link means the site root")
    func cloudLinkMeansRoot() {
        let link = "https://company.atlassian.net/jira/software/projects/APP/boards/1?selectedIssue=APP-7"
        #expect(site(link) == "https://company.atlassian.net")
    }

    @Test("A Data Center context path is kept, the page after it is not")
    func contextPathIsKept() {
        #expect(site("https://jira.company.com/jira/browse/APP-12") == "https://jira.company.com/jira")
        #expect(site("https://jira.company.com/jira/") == "https://jira.company.com/jira")
        #expect(site("https://jira.company.com/secure/Dashboard.jspa") == "https://jira.company.com")
    }

    @Test("Plain http is allowed for a local Jira only")
    func plainHTTPOnlyLocally() {
        #expect(site("http://localhost:8080/Dashboard.jspa") == "http://localhost:8080")
        #expect(site("http://127.0.0.1:2990/jira") == "http://127.0.0.1:2990/jira")
        #expect(site("http://jira.company.com") == nil)
    }

    @Test("Not a usable address", arguments: ["", "   ", "ftp://jira.company.com", "https://", "jira company com"])
    func notAUsableAddress(value: String) {
        #expect(JiraSite.url(from: value) == nil)
    }

    @Test("The API lives under rest/api/2 of the site")
    func apiURL() throws {
        let site = try #require(JiraSite.url(from: "https://jira.company.com/jira"))
        let url = JiraSite.apiURL(site, path: "/issue/APP-1/worklog", query: [URLQueryItem(name: "startAt", value: "0")])

        #expect(url?.absoluteString == "https://jira.company.com/jira/rest/api/2/issue/APP-1/worklog?startAt=0")
    }
}

@Suite("Jira credentials")
struct JiraCredentialsTests {
    @Test("Cloud needs an email, Data Center does not")
    func emailOnlyForCloud() {
        var credentials = JiraCredentials(site: "company.atlassian.net", token: "secret")
        #expect(!credentials.isConfigured)

        credentials.email = "dima@company.com"
        #expect(credentials.isConfigured)

        credentials.email = ""
        credentials.deployment = .dataCenter
        #expect(credentials.isConfigured)
    }

    @Test("The first missing piece is named")
    func problemNamesFirstMissingPiece() {
        #expect(JiraCredentials().problem == .missingSite)
        #expect(JiraCredentials(site: "http://jira.company.com", token: "secret").problem == .invalidSite)
        #expect(JiraCredentials(site: "company.atlassian.net", token: "secret").problem == .missingEmail)
        #expect(JiraCredentials(site: "company.atlassian.net", email: "dima@company.com").problem == .missingToken)
        #expect(JiraCredentials(site: "jira.company.com", token: "secret", deployment: .dataCenter).problem == nil)
    }

    @Test("Cloud signs in with Basic, Data Center with Bearer")
    func authorization() {
        let cloud = JiraCredentials(site: "x", email: "dima@company.com", token: "secret", deployment: .cloud)
        let dataCenter = JiraCredentials(site: "x", token: "secret", deployment: .dataCenter)

        #expect(cloud.authorization == "Basic ZGltYUBjb21wYW55LmNvbTpzZWNyZXQ=")
        #expect(dataCenter.authorization == "Bearer secret")
    }

    @Test("Whitespace around pasted values is dropped")
    func trimmed() {
        let credentials = JiraCredentials(site: " company.atlassian.net\n", email: " dima@company.com ", token: "secret\n")
            .trimmed()

        #expect(credentials == JiraCredentials(site: "company.atlassian.net", email: "dima@company.com", token: "secret"))
    }
}

@Suite("Jira worklog")
struct JiraWorklogTests {
    /// UTC so the tests do not depend on the machine time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let me = JiraUser(accountId: "me", key: nil, name: nil)
    private let issue = JiraIssueRef(key: "APP-1", summary: "Login screen")

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    private func decodePage(_ json: String) throws -> JiraWorklogPage {
        try JSONDecoder().decode(JiraWorklogPage.self, from: Data(json.utf8))
    }

    @Test("The query takes a day more on each side of the week")
    func queryIsPadded() {
        let jql = JiraWorklog.jql(from: date(7), to: date(14), calendar: calendar)

        #expect(jql == #"worklogAuthor = currentUser() AND worklogDate >= "2026-09-06" AND worklogDate < "2026-09-15""#)
    }

    @Test("Only the user's own entries inside the week are kept")
    func keepsOwnEntriesInsideWeek() throws {
        let page = try decodePage("""
        {"startAt": 0, "maxResults": 1000, "total": 4, "worklogs": [
          {"id": "101", "author": {"accountId": "me"}, "comment": "  Review\\n", "started": "2026-09-08T10:00:00.000+0000", "timeSpentSeconds": 5400},
          {"id": "102", "author": {"accountId": "someone"}, "started": "2026-09-08T11:00:00.000+0000", "timeSpentSeconds": 600},
          {"id": "103", "author": {"accountId": "me"}, "started": "2026-09-06T23:59:00.000+0000", "timeSpentSeconds": 600},
          {"id": "104", "author": {"accountId": "me"}, "started": "2026-09-14T00:00:00.000+0000", "timeSpentSeconds": 600}
        ]}
        """)

        let entries = JiraWorklog.entries(page.worklogs, issue: issue, author: me, from: date(7), to: date(14))

        #expect(entries.map(\.id) == [101])
        #expect(entries.first?.seconds == 5400)
        #expect(entries.first?.comment == "Review")
        #expect(entries.first?.issueKey == "APP-1")
        #expect(entries.first?.issueTitle == "Login screen")
    }

    @Test("The start keeps its offset")
    func startKeepsOffset() throws {
        let page = try decodePage("""
        {"total": 1, "worklogs": [
          {"id": "1", "author": {"accountId": "me"}, "started": "2026-09-07T01:30:00.000+0300", "timeSpentSeconds": 60}
        ]}
        """)

        // 01:30 in Moscow is still Sunday in UTC.
        #expect(JiraWorklog.entries(page.worklogs, issue: issue, author: me, from: date(7), to: date(14)).isEmpty)
    }

    @Test("A rich-text comment does not fail the page")
    func richTextCommentIsDropped() throws {
        let page = try decodePage("""
        {"total": 1, "worklogs": [
          {"id": "7", "author": {"accountId": "me"}, "comment": {"type": "doc", "version": 1, "content": []},
           "started": "2026-09-08T10:00:00.000+0000", "timeSpentSeconds": 60}
        ]}
        """)

        #expect(page.worklogs.count == 1)
        #expect(page.worklogs.first?.comment == nil)
    }

    @Test("Data Center authors are matched by key")
    func dataCenterMatchesByKey() throws {
        let me = JiraUser(accountId: nil, key: "JIRAUSER10100", name: "dima")
        let page = try decodePage("""
        {"total": 2, "worklogs": [
          {"id": "1", "author": {"key": "JIRAUSER10100", "name": "dima"}, "comment": "Done", "started": "2026-09-08T10:00:00.000+0000", "timeSpentSeconds": 3600},
          {"id": "2", "author": {"key": "JIRAUSER10200", "name": "anna"}, "started": "2026-09-08T10:00:00.000+0000", "timeSpentSeconds": 3600}
        ]}
        """)

        let entries = JiraWorklog.entries(page.worklogs, issue: issue, author: me, from: date(7), to: date(14))

        #expect(entries.map(\.id) == [1])
    }

    @Test("An account id outranks a matching name")
    func accountIDOutranksName() {
        let me = JiraUser(accountId: "me", key: nil, name: "dima")
        let namesake = JiraUser(accountId: "other", key: nil, name: "dima")

        #expect(!me.isSamePerson(as: namesake))
    }

    @Test("A search result without a summary falls back to the key")
    func searchPageIssueRefs() throws {
        let page = try JSONDecoder().decode(JiraSearchPage.self, from: Data("""
        {"issues": [
          {"id": "10001", "key": "APP-1", "fields": {"summary": "Login screen"}},
          {"id": "10002", "key": "APP-2"},
          {"id": "10003"}
        ], "isLast": true}
        """.utf8))

        #expect(page.issueRefs == [
            JiraIssueRef(key: "APP-1", summary: "Login screen"),
            JiraIssueRef(key: "APP-2", summary: "APP-2"),
            JiraIssueRef(key: "10003", summary: "10003")
        ])
    }
}

@Suite("Jira failures")
struct JiraFailureTests {
    @Test("Jira's own explanation is kept")
    func errorMessagesAreExtracted() {
        let body = #"{"errorMessages": ["Field 'worklogDate' is invalid."], "errors": {"jql": "Bad query"}}"#

        #expect(JiraError.from(status: 400, body: body) == .http(
            status: 400,
            message: "Field 'worklogDate' is invalid. jql: Bad query"
        ))
    }

    @Test("A body that is not Jira's JSON is kept as is")
    func otherBodyIsKept() {
        #expect(JiraError.message(from: "<html>Bad Gateway</html>") == "<html>Bad Gateway</html>")
        #expect(JiraError.message(from: #"{"errorMessages": [], "errors": {}}"#) == #"{"errorMessages": [], "errors": {}}"#)
    }

    @Test("Credential and address problems point to Settings", arguments: [
        JiraError.unauthorized, .forbidden, .notFound, .missingSite, .invalidSite, .missingEmail, .missingToken,
        .invalidURL, .unknownUser, .webPage, .redirected(location: "https://sso.company.com/login")
    ])
    func credentialProblemsNeedSettings(error: JiraError) {
        #expect(TrackerFailure(jira: error).needsSettings)
    }

    @Test("An unreadable JSON answer is not a settings problem")
    func decodingDoesNotNeedSettings() {
        #expect(!TrackerFailure(jira: JiraError.decoding("keyNotFound")).needsSettings)
    }

    @Test("A web page is told apart from the API's JSON")
    func webPageIsToldApart() {
        #expect(JiraError.isWebPage(contentType: "text/html;charset=UTF-8"))
        #expect(!JiraError.isWebPage(contentType: "application/json;charset=UTF-8"))
        #expect(!JiraError.isWebPage(contentType: nil))
    }

    @Test("The redirect target is kept for the technical details")
    func redirectKeepsLocation() {
        let failure = TrackerFailure(jira: JiraError.redirected(location: "https://sso.company.com/login"))

        #expect(failure.details.contains("https://sso.company.com/login"))
    }

    @Test("A server failure does not send the user to Settings")
    func serverFailureDoesNotNeedSettings() {
        let failure = TrackerFailure(jira: JiraError.from(status: 503, body: ""))

        #expect(!failure.needsSettings)
        #expect(failure.reason == "The server returned 503 Service Unavailable.")
    }

    @Test("Network and rate-limit messages name the service")
    func messagesNameService() {
        #expect(TrackerFailure(jira: URLError(.cannotFindHost)).reason == "Could not reach Jira.")
        #expect(TrackerFailure(URLError(.cannotFindHost)).reason == "Could not reach Tracker.")
        #expect(
            TrackerFailure(jira: JiraError.from(status: 429, body: "")).suggestion
                == "Jira is limiting requests. Wait a minute and try again."
        )
    }
}
