//
//  LinkedInProvider.swift
//  Toolbelt
//
//  LinkedIn through the official API with the member's own app: who the token belongs to,
//  and publishing and deleting the member's text posts.
//

import Foundation
import MCP

nonisolated struct LinkedInProvider: MCPProvider {
    let kind = MCPResourceKind.linkedin
    let defaultBaseURL = "https://api.linkedin.com"
    let supportsWrite = true
    let asksForAddress = false
    let asksForClientCredentials = true

    /// Stops a looping agent long before LinkedIn's own 150 requests a day.
    static let dailyPostLimit = 10

    private let formatter: LinkedInFormatter
    private let journal: LinkedInPostJournal
    private let session: URLSession?

    init(
        formatter: LinkedInFormatter = LinkedInFormatter(),
        journal: LinkedInPostJournal = .shared,
        session: URLSession? = nil
    ) {
        self.formatter = formatter
        self.journal = journal
        self.session = session
    }

    // MARK: Setup

    func tokenHint(for baseURL: URL?) -> MCPTokenHint {
        MCPTokenHint(
            text: """
            Needs your own LinkedIn app with the Sign In with LinkedIn using OpenID Connect and Share on LinkedIn \
            products. Copy Client ID and Client Secret from its Auth tab, then generate an access token in \
            OAuth Token Generator (Docs and tools → OAuth Token Tools) for that app with the scopes openid profile \
            email w_member_social. The token lasts 60 days.
            """,
            url: LinkedInGuide.developerApps,
            linkTitle: "Open LinkedIn Developers",
            placeholder: "From OAuth Token Generator"
        )
    }

    func guide(for baseURL: URL?) -> MCPGuide {
        LinkedInGuide.guide(dailyPostLimit: Self.dailyPostLimit)
    }

    func validate(_ setup: MCPSetup) async throws -> MCPValidation {
        let client = makeClient(token: setup.token)
        let userInfo = try await client.userInfo()

        var introspection: LinkedInIntrospection?
        if let clientID = setup.clientID, let clientSecret = setup.clientSecret {
            introspection = try await client.introspect(clientID: clientID, clientSecret: clientSecret)
        }

        let account = LinkedInSetupCheck.account(userInfo: userInfo, introspection: introspection, checkedAt: Date())
        return MCPValidation(
            account: account,
            warnings: LinkedInSetupCheck.warnings(account: account, introspection: introspection)
        )
    }

    func accountLine(_ resource: MCPResource) -> String {
        guard let account = resource.account else { return "linkedin.com" }
        return summary(account) ?? "linkedin.com"
    }

    func accountSummary(_ account: MCPAccount) -> String {
        summary(account) ?? "LinkedIn member"
    }

    func writeAccessWarning(for resource: MCPResource) -> String {
        let name = resource.account?.displayName ?? resource.name
        return "Claude will be able to publish and delete posts as \(name). A client can ask you to confirm each call."
    }

    private func summary(_ account: MCPAccount) -> String? {
        let parts = [account.displayName, account.username].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Tools

    func owns(toolName: String) -> Bool {
        toolName.hasPrefix("linkedin_")
    }

    func tools(for resources: [MCPResource]) -> [Tool] {
        let names = Set(LinkedInAccess.toolNames(for: resources))
        let all = resources.map(\.name).joined(separator: ", ")
        let writable = resources.filter(\.allowWrite).map(\.name).joined(separator: ", ")
        let account = JSONSchema.string(
            resources.count == 1
                ? "LinkedIn account, by resource name. Optional: only \(all) is enabled."
                : "LinkedIn account, by resource name. Required, several are enabled: \(all)."
        )
        let writeAccount = JSONSchema.string(
            resources.count == 1
                ? "LinkedIn account, by resource name. Optional: only \(all) is enabled."
                : "LinkedIn account, by resource name. Required, several are enabled: \(all). Writing is allowed for: \(writable)."
        )
        let readOnly = Tool.Annotations(readOnlyHint: true, openWorldHint: true)

        let tools = [
            Tool(
                name: "linkedin_accounts",
                description: """
                List the LinkedIn accounts the user enabled in Toolbelt: resource name, member name, email, author URN, \
                token scopes and expiry, and whether writing is allowed. Tokens and secrets are never shown.
                """,
                inputSchema: JSONSchema.object([:]),
                annotations: readOnly
            ),
            Tool(
                name: "linkedin_profile",
                description: "The member the token belongs to, as LinkedIn reports it now: name, email, locale, photo and the author URN.",
                inputSchema: JSONSchema.object(["account": account]),
                annotations: readOnly
            ),
            Tool(
                name: "linkedin_recent_posts",
                description: """
                Posts published through Toolbelt, newest first: time, visibility, URN, link and the first 200 characters. \
                LinkedIn's API does not let Toolbelt read the member's feed or other posts, so only these are known.
                """,
                inputSchema: JSONSchema.object([
                    "account": account,
                    "limit": JSONSchema.integer("How many posts to return.", minimum: 1, maximum: 50, default: 10)
                ]),
                annotations: readOnly
            ),
            Tool(
                name: "linkedin_create_post",
                description: """
                Publish a text post on the member's LinkedIn feed, as the member. Before publishing, show the user the \
                final text and who will see it, and wait for their agreement: dry_run returns the text as LinkedIn will \
                receive it without posting. The text is taken literally — Toolbelt escapes LinkedIn's reserved \
                characters, #word stays a hashtag, mentions are not supported. At most \(LittleText.maxLength) characters.
                """,
                inputSchema: JSONSchema.object([
                    "account": writeAccount,
                    "text": JSONSchema.string("The post text, plain."),
                    "visibility": JSONSchema.string(
                        "Who sees the post: PUBLIC is anyone on or off LinkedIn, CONNECTIONS is the member's connections only.",
                        values: LinkedInVisibility.allCases.map(\.rawValue)
                    ),
                    "dry_run": JSONSchema.boolean("Return the text as it would be published, without publishing.")
                ], required: ["text", "visibility"]),
                annotations: Tool.Annotations(
                    readOnlyHint: false,
                    destructiveHint: false,
                    idempotentHint: false,
                    openWorldHint: true
                )
            ),
            Tool(
                name: "linkedin_delete_post",
                description: """
                Delete one of the member's posts by its URN (urn:li:share:… or urn:li:ugcPost:…) or a \
                linkedin.com/feed/update/<URN> link. linkedin_recent_posts lists the URNs of posts published through Toolbelt.
                """,
                inputSchema: JSONSchema.object([
                    "account": writeAccount,
                    "post": JSONSchema.string("Post URN or a linkedin.com/feed/update/… link.")
                ], required: ["post"]),
                annotations: Tool.Annotations(
                    readOnlyHint: false,
                    destructiveHint: true,
                    idempotentHint: true,
                    openWorldHint: true
                )
            )
        ]
        return tools.filter { names.contains($0.name) }
    }

    func call(_ name: String, arguments values: [String: Value], credentials: [MCPCredential]) async -> MCPToolOutput {
        let arguments = ToolArguments(values: values)
        do {
            switch name {
            case "linkedin_accounts":
                let enabled = credentials.filter(\.resource.isEnabled)
                let withoutToken = Set(enabled.filter { $0.token == nil }.map(\.resource.id))
                return .success(formatter.accounts(
                    enabled.map(\.resource),
                    withoutToken: withoutToken,
                    disabledCount: credentials.count - enabled.count
                ))
            case "linkedin_profile":
                let (resource, token) = try select(arguments, credentials, forWriting: false)
                let info = try await makeClient(token: token).userInfo()
                return .success("Account in Toolbelt: \(resource.name)\n" + formatter.profile(info))
            case "linkedin_recent_posts":
                let (resource, _) = try select(arguments, credentials, forWriting: false)
                let limit = try arguments.int("limit", default: 10, in: 1...50)
                let records = journal.records(for: resource.id)
                return .success(formatter.recentPosts(Array(records.prefix(limit)), account: resource.name, total: records.count))
            case "linkedin_create_post":
                return try await createPost(arguments, credentials)
            case "linkedin_delete_post":
                return try await deletePost(arguments, credentials)
            default:
                return .failure("Toolbelt has no tool named \(name).")
            }
        } catch {
            return .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: Writing

    private func createPost(_ arguments: ToolArguments, _ credentials: [MCPCredential]) async throws -> MCPToolOutput {
        let (resource, token) = try select(arguments, credentials, forWriting: true)
        let text = try arguments.requiredString("text")
        let visibilityText = try arguments.requiredString("visibility")
        guard let visibility = LinkedInVisibility(argument: visibilityText) else {
            throw MCPToolError("“visibility” has to be PUBLIC or CONNECTIONS, not “\(visibilityText)”.")
        }
        if let problem = LittleText.problem(with: text) {
            throw MCPToolError(problem)
        }

        let client = makeClient(token: token)
        let authorURN = try await resolveAuthorURN(of: resource, client: client)
        let author = resource.account?.displayName ?? resource.name
        let escaped = LittleText.escape(text)

        if try arguments.bool("dry_run") == true {
            return .success(formatter.dryRun(
                text: text,
                escaped: escaped,
                author: author,
                authorURN: authorURN,
                visibility: visibility
            ))
        }

        let now = Date()
        try journal.reservePublication(for: resource.id, limit: Self.dailyPostLimit, at: now)
        let body = LinkedInPostBody(author: authorURN, commentary: escaped, visibility: visibility)
        let createdURN: String?
        do {
            createdURN = try await client.createPost(body)
        } catch {
            if (error as? LinkedInError)?.leavesOutcomeUnknown != true {
                journal.cancelPublication(at: now, for: resource.id)
            }
            throw error
        }

        guard let urn = createdURN else {
            return .success(formatter.publishedWithoutURN(author: author, visibility: visibility, at: now))
        }
        journal.add(LinkedInPostRecord(urn: urn, createdAt: now, visibility: visibility, text: text), for: resource.id)
        return .success(formatter.published(urn: urn, author: author, visibility: visibility, at: now))
    }

    private func deletePost(_ arguments: ToolArguments, _ credentials: [MCPCredential]) async throws -> MCPToolOutput {
        let (resource, token) = try select(arguments, credentials, forWriting: true)
        let post = try arguments.requiredString("post")

        switch LinkedInLink.parse(post) {
        case let .post(urn):
            var wasAlreadyGone = false
            do {
                try await makeClient(token: token).deletePost(urn)
            } catch LinkedInError.notFound {
                wasAlreadyGone = true
            }
            let wasInJournal = journal.remove(urn: urn, for: resource.id)
            return .success(formatter.deleted(
                urn,
                account: resource.name,
                wasInJournal: wasInJournal,
                wasAlreadyGone: wasAlreadyGone
            ))
        case .activity:
            throw MCPToolError(
                "That link carries an activity id, which LinkedIn's Posts API does not take. "
                    + "Use the post URN from linkedin_recent_posts (urn:li:share:… or urn:li:ugcPost:…)."
            )
        case nil:
            throw MCPToolError("“\(post)” is neither a LinkedIn post URN nor a linkedin.com/feed/update/… link.")
        }
    }

    /// Saved at Check; asked again if the resource was saved without it.
    private func resolveAuthorURN(of resource: MCPResource, client: LinkedInClient) async throws -> String {
        if let subject = resource.account?.subjectID, !subject.isEmpty {
            return "urn:li:person:\(subject)"
        }
        return try await client.userInfo().authorURN
    }

    // MARK: Accounts

    private func select(
        _ arguments: ToolArguments,
        _ credentials: [MCPCredential],
        forWriting: Bool
    ) throws -> (MCPResource, String) {
        let resource = try LinkedInAccess.resource(
            account: arguments.string("account"),
            in: credentials.map(\.resource),
            forWriting: forWriting
        )
        guard let token = credentials.first(where: { $0.resource.id == resource.id })?.token else {
            throw MCPToolError("There is no token for the LinkedIn account “\(resource.name)” in Keychain. Add it in Toolbelt → MCP.")
        }
        if let account = resource.account, account.isExpired() {
            throw MCPToolError(
                "The LinkedIn token of “\(resource.name)” has expired: access tokens last 60 days. Generate a new one in "
                    + "OAuth Token Generator (\(LinkedInError.tokenGenerator)) and paste it in Toolbelt → MCP."
            )
        }
        return (resource, token)
    }

    private func makeClient(token: String) -> LinkedInClient {
        LinkedInClient(token: token, session: session)
    }
}
