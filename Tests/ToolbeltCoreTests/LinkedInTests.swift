import Foundation
import Testing
@testable import ToolbeltCore

@Suite("LinkedIn post text")
struct LittleTextTests {
    @Test("Every reserved character is escaped")
    func reserved() {
        for character in LittleText.reserved {
            #expect(LittleText.escape("a\(character)b") == "a\\\(character)b")
        }
    }

    @Test("#word stays a hashtag, a lone # does not")
    func hashtags() {
        #expect(LittleText.escape("#swift") == "#swift")
        #expect(LittleText.escape("Привет, #свифт!") == "Привет, #свифт!")
        #expect(LittleText.escape("C# and F#") == "C\\# and F\\#")
        #expect(LittleText.escape("# heading") == "\\# heading")
        #expect(LittleText.escape("(see #ios_dev)") == "\\(see #ios\\_dev\\)")
        #expect(LittleText.escape("https://x.com/a#b") == "https://x.com/a\\#b")
    }

    @Test("A backslash is doubled")
    func backslash() {
        #expect(LittleText.escape("a\\b") == "a\\\\b")
    }

    @Test("Length is counted in characters, up to 3000")
    func length() {
        #expect(LittleText.problem(with: String(repeating: "я", count: 3_000)) == nil)
        #expect(LittleText.problem(with: String(repeating: "👍🏽", count: 3_000)) == nil)
        #expect(LittleText.problem(with: String(repeating: "a", count: 3_001))?.contains("3001") == true)
        #expect(LittleText.problem(with: "  \n") == "The post text is empty.")
    }
}

@Suite("LinkedIn post links")
struct LinkedInLinkTests {
    @Test("URNs of shares and UGC posts")
    func urns() {
        #expect(LinkedInLink.parse("urn:li:share:7123456789012345678") == .post("urn:li:share:7123456789012345678"))
        #expect(LinkedInLink.parse(" urn:li:ugcPost:7123 ") == .post("urn:li:ugcPost:7123"))
        #expect(LinkedInLink.parse("urn:li:UGCPOST:7123") == .post("urn:li:ugcPost:7123"))
    }

    @Test("feed/update links: with a slash or without, with a query, with the URN encoded")
    func links() {
        let expected = LinkedInPostReference.post("urn:li:share:7123")
        #expect(LinkedInLink.parse("https://www.linkedin.com/feed/update/urn:li:share:7123/") == expected)
        #expect(LinkedInLink.parse("https://www.linkedin.com/feed/update/urn:li:share:7123") == expected)
        #expect(LinkedInLink.parse("https://www.linkedin.com/feed/update/urn:li:share:7123/?utm_source=share") == expected)
        #expect(LinkedInLink.parse("https://www.linkedin.com/feed/update/urn%3Ali%3Ashare%3A7123/") == expected)
        #expect(LinkedInLink.parse("https://linkedin.com/feed/update/urn:li:ugcPost:99") == .post("urn:li:ugcPost:99"))
        #expect(LinkedInLink.parse("linkedin.com/feed/update/urn:li:share:7123") == expected)
        #expect(LinkedInLink.parse("www.linkedin.com/feed/update/urn:li:share:7123/") == expected)
        #expect(LinkedInLink.postURL("urn:li:share:7123") == "https://www.linkedin.com/feed/update/urn:li:share:7123/")
    }

    @Test("Activity links get an answer of their own")
    func activity() {
        #expect(LinkedInLink.parse("https://www.linkedin.com/posts/dima_swift-activity-7123456789-AbCd") == .activity("7123456789"))
        #expect(LinkedInLink.parse("https://www.linkedin.com/feed/update/urn:li:activity:7123/") == .activity("7123"))
        #expect(LinkedInLink.parse("urn:li:activity:7123") == .activity("7123"))
    }

    @Test("Anything else is not a post")
    func garbage() {
        #expect(LinkedInLink.parse("hello") == nil)
        #expect(LinkedInLink.parse("urn:li:share:") == nil)
        #expect(LinkedInLink.parse("urn:li:person:abc") == nil)
        #expect(LinkedInLink.parse("https://www.linkedin.com/in/dima") == nil)
        #expect(LinkedInLink.parse("https://evil.com/feed/update/urn:li:share:1") == nil)
        #expect(LinkedInLink.parse("https://notlinkedin.com/feed/update/urn:li:share:1") == nil)
    }
}

@Suite("LinkedIn token check")
struct LinkedInSetupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func user() throws -> LinkedInUserInfo {
        let json = #"""
        {"sub":"782bbtaQ","name":"John Doe","given_name":"John","family_name":"Doe",
         "picture":"https://media.licdn.com/p.jpg","locale":"en-US","email":"doe@email.com","email_verified":true}
        """#
        return try decoder().decode(LinkedInUserInfo.self, from: Data(json.utf8))
    }

    @Test("userinfo gives the author URN; the locale comes as a string or an object")
    func userInfo() throws {
        let user = try Self.user()
        #expect(user.authorURN == "urn:li:person:782bbtaQ")
        #expect(user.displayName == "John Doe")
        #expect(user.locale?.value == "en-US")
        #expect(user.emailVerified == true)

        let json = #"{"sub":"x","given_name":"Ann","locale":{"country":"US","language":"en"}}"#
        let other = try Self.decoder().decode(LinkedInUserInfo.self, from: Data(json.utf8))
        #expect(other.locale?.value == "en-US")
        #expect(other.displayName == "Ann")
        #expect(other.email == nil)
    }

    @Test("Introspection becomes the token's expiry and scopes")
    func introspection() throws {
        let json = #"""
        {"active":true,"client_id":"86abc","authorized_at":1799000000,"created_at":1799000000,
         "status":"active","expires_at":1805184000,"scope":"email,openid,profile,w_member_social","auth_type":"3L"}
        """#
        let introspection = try Self.decoder().decode(LinkedInIntrospection.self, from: Data(json.utf8))
        let account = LinkedInSetupCheck.account(userInfo: try Self.user(), introspection: introspection, checkedAt: now)

        #expect(account.expiry == .on(Date(timeIntervalSince1970: 1_805_184_000)))
        #expect(account.scopes == ["email", "openid", "profile", "w_member_social"])
        #expect(account.subjectID == "782bbtaQ")
        #expect(account.username == "doe@email.com")
        #expect(account.displayName == "John Doe")
        #expect(LinkedInSetupCheck.warnings(account: account, introspection: introspection, now: now).isEmpty)
    }

    @Test("A token of another app, an expired one, one without w_member_social, one about to expire")
    func warnings() throws {
        let user = try Self.user()
        func check(_ introspection: LinkedInIntrospection) -> (MCPAccount, [String]) {
            let account = LinkedInSetupCheck.account(userInfo: user, introspection: introspection, checkedAt: now)
            return (account, LinkedInSetupCheck.warnings(account: account, introspection: introspection, now: now))
        }

        let (foreign, foreignWarnings) = check(LinkedInIntrospection(active: false))
        #expect(foreign.expiry == .unknown)
        #expect(foreign.scopes == nil)
        #expect(foreignWarnings.count == 1)
        #expect(foreignWarnings.first?.contains("another app") == true)

        let (_, expiredWarnings) = check(LinkedInIntrospection(active: false, status: "expired"))
        #expect(expiredWarnings == ["LinkedIn reports the token as expired."])

        let readOnly = LinkedInIntrospection(active: true, status: "active", expiresAt: 1_805_184_000, scope: "openid profile")
        let (_, scopeWarnings) = check(readOnly)
        #expect(scopeWarnings.count == 1)
        #expect(scopeWarnings.first?.contains("w_member_social") == true)

        let soon = LinkedInIntrospection(
            active: true,
            status: "active",
            expiresAt: now.addingTimeInterval(5.5 * 86_400).timeIntervalSince1970,
            scope: "openid,profile,w_member_social"
        )
        let (_, soonWarnings) = check(soon)
        #expect(soonWarnings == ["The token expires in 5 days."])
    }
}

@Suite("LinkedIn client")
struct LinkedInClientTests {
    @Test("The post body is the one the Posts API documents")
    func postBody() throws {
        let body = LinkedInPostBody(author: "urn:li:person:782bbtaQ", commentary: "Hello", visibility: .connections)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(body), as: UTF8.self)
        let expected = #"{"author":"urn:li:person:782bbtaQ","commentary":"Hello","#
            + #""distribution":{"feedDistribution":"MAIN_FEED","targetEntities":[],"thirdPartyDistributionChannels":[]},"#
            + #""isReshareDisabledByAuthor":false,"lifecycleState":"PUBLISHED","visibility":"CONNECTIONS"}"#
        #expect(json == expected)
    }

    @Test("HTTP answers become errors that say what to do")
    func statusMapping() {
        func error(_ status: Int, _ endpoint: LinkedInEndpoint, _ body: String = "", retryAfter: String? = nil) -> LinkedInError? {
            LinkedInClient.error(status: status, endpoint: endpoint, body: Data(body.utf8), retryAfter: retryAfter)
        }

        #expect(error(201, .createPost) == nil)
        #expect(error(204, .deletePost) == nil)
        #expect(error(401, .userInfo) == .tokenRejected)
        #expect(error(401, .createPost) == .tokenRejected)
        #expect(error(403, .userInfo) == .missingProfileScope)
        #expect(error(403, .createPost) == .missingShareScope)
        #expect(error(403, .deletePost) == .notYourPost)
        #expect(error(401, .introspection) == .wrongClientSecret)
        #expect(error(400, .introspection, #"{"error":"invalid_request","error_description":"Unable to retrieve access token"}"#) == .wrongClientIDOrToken)
        #expect(error(429, .createPost, retryAfter: "30") == .rateLimited(retryAfter: 30))
        #expect(error(426, .createPost, #"{"status":426,"code":"NONEXISTENT_VERSION","message":"Requested version 20250101 is not active"}"#)
            == .outdatedVersion(LinkedInClient.apiVersion))
        #expect(error(422, .createPost, #"{"status":422,"message":"Content is a duplicate of urn:li:share:1"}"#)
            == .rejected(status: 422, message: "Content is a duplicate of urn:li:share:1"))
        #expect(error(404, .deletePost) == .notFound)
        #expect(error(404, .userInfo) == .server(status: 404, message: nil))
        #expect(error(503, .userInfo) == .server(status: 503, message: nil))
    }

    @Test("Error texts never carry the token or the client secret")
    func errorTexts() {
        let all: [LinkedInError] = [
            .tokenRejected, .missingProfileScope, .missingShareScope, .notYourPost, .forbidden(message: "Not enough permissions"),
            .notFound, .rejected(status: 422, message: "duplicate"), .outdatedVersion("202608"), .rateLimited(retryAfter: 60),
            .server(status: 500, message: "boom"), .network(reason: "offline"), .redirected(location: "https://elsewhere.example"),
            .invalidResponse, .wrongClientSecret, .wrongClientIDOrToken
        ]
        for error in all {
            let text = error.errorDescription ?? ""
            #expect(!text.isEmpty)
            #expect(!text.contains("AQXsecret-token-value"))
            #expect(!text.contains("WPL_AP1.client-secret"))
        }
        #expect(LinkedInError.tokenRejected.errorDescription?.contains("Token Generator") == true)
        #expect(LinkedInError.outdatedVersion("202608").errorDescription?.contains("Update Toolbelt") == true)
    }

    @Test("The introspection form and a post URN in a path are percent-encoded")
    func encoding() {
        #expect(LinkedInClient.formBody([("client_id", "86abc"), ("token", "AQ+x/y=")]) == "client_id=86abc&token=AQ%2Bx%2Fy%3D")
        #expect(LinkedInClient.encodeSegment("urn:li:share:7123") == "urn%3Ali%3Ashare%3A7123")
    }
}

@Suite("LinkedIn access")
struct LinkedInAccessTests {
    private func resource(_ name: String, enabled: Bool = true, write: Bool = false) -> MCPResource {
        MCPResource(
            kind: .linkedin,
            name: name,
            baseURL: URL(string: "https://api.linkedin.com")!,
            isEnabled: enabled,
            allowWrite: write
        )
    }

    @Test("Write tools are listed only while a resource allows writing")
    func toolList() {
        #expect(LinkedInAccess.toolNames(for: []).isEmpty)
        #expect(LinkedInAccess.toolNames(for: [resource("work")]) == LinkedInAccess.readTools)
        #expect(LinkedInAccess.toolNames(for: [resource("work"), resource("me", write: true)])
            == LinkedInAccess.readTools + LinkedInAccess.writeTools)
    }

    @Test("A call writes only through a resource with Allow write on")
    func writing() throws {
        let work = resource("Work")
        let me = resource("me", write: true)

        #expect(throws: LinkedInAccessError.writeNotAllowed("Work")) {
            try LinkedInAccess.resource(account: nil, in: [work], forWriting: true)
        }
        #expect(try LinkedInAccess.resource(account: nil, in: [work], forWriting: false) == work)
        #expect(throws: LinkedInAccessError.writeNotAllowed("Work")) {
            try LinkedInAccess.resource(account: "work", in: [work, me], forWriting: true)
        }
        #expect(try LinkedInAccess.resource(account: "ME", in: [work, me], forWriting: true) == me)
    }

    @Test("Several accounts need account; unknown and turned-off ones are named")
    func selection() {
        let work = resource("work")
        let me = resource("me", write: true)
        let old = resource("old", enabled: false)

        #expect(throws: LinkedInAccessError.accountRequired(enabled: ["work", "me"])) {
            try LinkedInAccess.resource(account: nil, in: [work, me, old], forWriting: false)
        }
        #expect(throws: LinkedInAccessError.unknownAccount("boss", enabled: ["work", "me"])) {
            try LinkedInAccess.resource(account: "boss", in: [work, me, old], forWriting: false)
        }
        #expect(throws: LinkedInAccessError.turnedOff("old")) {
            try LinkedInAccess.resource(account: "old", in: [work, me, old], forWriting: false)
        }
        #expect(throws: LinkedInAccessError.noneEnabled) {
            try LinkedInAccess.resource(account: nil, in: [old], forWriting: false)
        }
    }
}

@Suite("LinkedIn post journal")
struct LinkedInPostJournalTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ index: Int, minutes: Double) -> LinkedInPostRecord {
        LinkedInPostRecord(
            urn: "urn:li:share:\(index)",
            createdAt: start.addingTimeInterval(minutes * 60),
            visibility: .public,
            text: "Post \(index)"
        )
    }

    @Test("Newest first, at most 100, removed by URN, erased with the resource")
    func records() throws {
        let suite = "toolbelt.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = LinkedInPostJournal(defaults: defaults)
        let id = UUID()

        for index in 0..<105 {
            journal.add(record(index, minutes: Double(index)), for: id)
        }
        let records = journal.records(for: id)
        #expect(records.count == LinkedInPostJournal.recordLimit)
        #expect(records.first?.urn == "urn:li:share:104")
        #expect(records.last?.urn == "urn:li:share:5")

        #expect(journal.remove(urn: "urn:li:share:104", for: id))
        #expect(journal.records(for: id).first?.urn == "urn:li:share:103")
        #expect(journal.remove(urn: "urn:li:share:104", for: id) == false)
        #expect(journal.records(for: UUID()).isEmpty)

        LinkedInPostJournal.erase(id, in: defaults)
        #expect(journal.records(for: id).isEmpty)
        #expect(journal.publishedInLastDay(for: id, now: start) == 0)
    }

    @Test("The daily limit: reserved before posting, freed only by a turned-down request, not by a deletion")
    func dailyLimit() throws {
        let suite = "toolbelt.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let journal = LinkedInPostJournal(defaults: defaults)
        let id = UUID()

        for minute in 0..<3 {
            try journal.reservePublication(for: id, limit: 3, at: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(throws: LinkedInAccessError.dailyLimit(3)) {
            try journal.reservePublication(for: id, limit: 3, at: start.addingTimeInterval(600))
        }

        journal.add(record(1, minutes: 0), for: id)
        journal.remove(urn: "urn:li:share:1", for: id)
        #expect(journal.publishedInLastDay(for: id, now: start.addingTimeInterval(600)) == 3)

        journal.cancelPublication(at: start.addingTimeInterval(120), for: id)
        #expect(journal.publishedInLastDay(for: id, now: start.addingTimeInterval(600)) == 2)
        try journal.reservePublication(for: id, limit: 3, at: start.addingTimeInterval(600))

        #expect(journal.publishedInLastDay(for: id, now: start.addingTimeInterval(24 * 3_600 + 30)) == 2)
        #expect(journal.publishedInLastDay(for: id, now: start.addingTimeInterval(25 * 3_600)) == 0)
    }

    @Test("Only the beginning of the text is kept")
    func excerpt() {
        let long = LinkedInPostRecord(urn: "urn:li:share:1", createdAt: start, visibility: .connections, text: String(repeating: "a", count: 500))
        #expect(long.excerpt.count == LinkedInPostRecord.excerptLength)
    }
}

@Suite("LinkedIn answers")
struct LinkedInFormatterTests {
    @Test("A published post: who, for whom, when, the URN and the link")
    func published() throws {
        let formatter = LinkedInFormatter(timeZone: try #require(TimeZone(identifier: "Europe/Moscow")))
        let text = formatter.published(
            urn: "urn:li:share:7",
            author: "Dmitriy Medyannik",
            visibility: .connections,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(text == """
        Posted to LinkedIn as Dmitriy Medyannik · visible to connections · 2027-01-15 11:00+03:00
        urn:li:share:7
        https://www.linkedin.com/feed/update/urn:li:share:7/
        """)
    }

    @Test("Accounts show who and what is allowed, and say so when the journal is empty")
    func accounts() {
        var resource = MCPResource(kind: .linkedin, name: "me", baseURL: URL(string: "https://api.linkedin.com")!, allowWrite: true)
        resource.account = MCPAccount(
            username: "dima@example.com",
            displayName: "Dima",
            subjectID: "782bbtaQ",
            scopes: ["openid", "w_member_social"],
            expiry: .on(Date(timeIntervalSince1970: 1_805_184_000)),
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let formatter = LinkedInFormatter(timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let text = formatter.accounts([resource], disabledCount: 1, now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(text.contains("me · Dima · dima@example.com · urn:li:person:782bbtaQ · scopes: openid, w_member_social · token expires 2027-03-16 · writing allowed"))
        #expect(text.contains("1 more turned off"))
        #expect(formatter.recentPosts([], account: "me", total: 0).contains("LinkedIn's API does not let Toolbelt read"))
    }
}
