//
//  GitLabProvider.swift
//  Toolbelt
//
//  Read-only GitLab tools: pipelines, jobs and their logs, merge requests.
//

import Foundation
import MCP

nonisolated struct GitLabProvider: MCPProvider {
    let kind = MCPResourceKind.gitlab
    let defaultBaseURL = "https://gitlab.com"
    let supportsWrite = false
    let asksForAddress = true
    let asksForClientCredentials = false

    static let pipelineStatuses = [
        "created", "waiting_for_resource", "preparing", "pending", "running",
        "success", "failed", "canceled", "skipped", "manual", "scheduled"
    ]
    static let mergeRequestStates = ["opened", "closed", "merged", "locked", "all"]

    private let formatter: GitLabFormatter
    private let session: URLSession?

    init(formatter: GitLabFormatter = GitLabFormatter(), session: URLSession? = nil) {
        self.formatter = formatter
        self.session = session
    }

    // MARK: Setup

    func tokenHint(for baseURL: URL?) -> MCPTokenHint {
        let base = baseURL ?? URL(string: defaultBaseURL)
        let page = base.flatMap(GitLabGuide.tokenPage(for:))
        let host = base.flatMap(GitLabLinkParser.host(of:)) ?? "your GitLab"
        return MCPTokenHint(
            text: "Needs a legacy personal access token with the read_api scope. Create one on \(host) under User Settings → Access Tokens.",
            url: page,
            placeholder: "glpat-…"
        )
    }

    func guide(for baseURL: URL?) -> MCPGuide {
        GitLabGuide.guide(for: baseURL ?? URL(string: defaultBaseURL))
    }

    func validate(_ setup: MCPSetup) async throws -> MCPValidation {
        let client = makeClient(baseURL: setup.baseURL, token: setup.token)
        let user: GitLabUser = try await client.get("user")

        var tokenInfo: GitLabTokenInfo?
        do {
            tokenInfo = try await client.get("personal_access_tokens/self")
        } catch GitLabError.notFound, GitLabError.forbidden {
            // Older GitLab versions and non-PAT tokens do not have this endpoint.
            tokenInfo = nil
        }

        let expiry: MCPTokenExpiry
        if let tokenInfo {
            expiry = tokenInfo.expiresAt.flatMap(Self.expiryDate).map(MCPTokenExpiry.on) ?? .never
        } else {
            expiry = .unknown
        }

        let account = MCPAccount(
            username: user.username,
            displayName: user.name,
            tokenName: tokenInfo?.name,
            scopes: tokenInfo?.scopes,
            expiry: expiry,
            checkedAt: Date()
        )

        var warnings: [String] = []
        if let scopes = tokenInfo?.scopes, !scopes.contains("read_api"), !scopes.contains("api") {
            warnings.append("The token has no read_api scope, so GitLab will answer 403 to every tool.")
        }
        if tokenInfo?.active == false || tokenInfo?.revoked == true {
            warnings.append("GitLab reports the token as inactive.")
        }
        if account.isExpired() {
            warnings.append("The token has expired.")
        } else if account.expiresSoon(), let days = account.daysLeft() {
            warnings.append("The token expires in \(days) \(days == 1 ? "day" : "days").")
        }
        return MCPValidation(account: account, warnings: warnings)
    }

    func accountLine(_ resource: MCPResource) -> String {
        var parts = [resource.host]
        if let account = resource.account {
            parts.append("@\(account.username)")
        }
        return parts.joined(separator: " · ")
    }

    func accountSummary(_ account: MCPAccount) -> String {
        if let name = account.displayName, !name.isEmpty {
            return "@\(account.username) · \(name)"
        }
        return "@\(account.username)"
    }

    func writeAccessWarning(for resource: MCPResource) -> String {
        "Toolbelt has no GitLab tools that change data yet."
    }

    /// GitLab stores the date only; the token stops working at the start of that day, UTC.
    static func expiryDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: Tools

    func owns(toolName: String) -> Bool {
        toolName.hasPrefix("gitlab_")
    }

    func tools(for resources: [MCPResource]) -> [Tool] {
        let names = resources.map { "\($0.name) (\($0.host))" }.joined(separator: ", ")
        let instance = JSONSchema.string(
            resources.count == 1
                ? "GitLab instance, by resource name or host. Optional: only \(names) is enabled."
                : "GitLab instance, by resource name or host. Required, several are enabled: \(names)."
        )
        let project = JSONSchema.string("Project path, e.g. group/subgroup/project, or its numeric id.")
        let readOnly = Tool.Annotations(readOnlyHint: true, openWorldHint: true)

        return [
            Tool(
                name: "gitlab_instances",
                description: "List the GitLab instances the user enabled in Toolbelt: name, host and the user the token belongs to. Tokens are never shown.",
                inputSchema: JSONSchema.object([:]),
                annotations: readOnly
            ),
            Tool(
                name: "gitlab_resolve_url",
                description: """
                Open a GitLab link the user pasted — a pipeline, job, merge request or commit — and return what the \
                matching tool returns: a pipeline with all its jobs and triggers, a job log, a merge request with its \
                changed files, or a commit with its pipelines. The instance is picked by the link's host. Prefer this \
                tool whenever the user gives a GitLab link.
                """,
                inputSchema: JSONSchema.object(["url": JSONSchema.string("Any GitLab web link.")], required: ["url"]),
                annotations: readOnly
            ),
            Tool(
                name: "gitlab_pipelines",
                description: "Latest pipelines of a project, newest first: id, status, ref, sha, author, creation time and duration.",
                inputSchema: JSONSchema.object([
                    "instance": instance,
                    "project": project,
                    "ref": JSONSchema.string("Only pipelines for this branch or tag."),
                    "status": JSONSchema.string("Only pipelines in this status.", values: Self.pipelineStatuses),
                    "limit": JSONSchema.integer("How many pipelines to return.", minimum: 1, maximum: 50, default: 10)
                ], required: ["project"]),
                annotations: readOnly
            ),
            Tool(
                name: "gitlab_pipeline",
                description: """
                One pipeline: status, ref, sha and commit message, then every job and trigger job with stage, status, \
                duration and failure_reason, failed ones first. A trigger job shows its downstream pipeline, or that \
                none was created.
                """,
                inputSchema: JSONSchema.object([
                    "instance": instance,
                    "project": project,
                    "pipeline_id": JSONSchema.identifier("Pipeline id, as in /-/pipelines/<id>.")
                ], required: ["project", "pipeline_id"]),
                annotations: readOnly
            ),
            Tool(
                name: "gitlab_job_log",
                description: """
                The log of one job without ANSI colors and GitLab section markers, under a header with the job name, \
                status, failure_reason, runner and duration. By default the last lines of the log; with grep, only the \
                lines matching the regular expression, numbered like grep -n, with context lines around them.
                """,
                inputSchema: JSONSchema.object([
                    "instance": instance,
                    "project": project,
                    "job_id": JSONSchema.identifier("Job id, as in /-/jobs/<id>."),
                    "tail": JSONSchema.integer(
                        "How many last lines to return when grep is not set.",
                        minimum: 1, maximum: JobLog.maxTail, default: JobLog.defaultTail
                    ),
                    "grep": JSONSchema.string("Regular expression (ICU syntax); only matching lines are returned. Prefix with (?i) to ignore case."),
                    "context": JSONSchema.integer(
                        "Lines of context around every grep match.",
                        minimum: 0, maximum: JobLog.maxContext, default: JobLog.defaultContext
                    )
                ], required: ["project", "job_id"]),
                annotations: readOnly
            ),
            Tool(
                name: "gitlab_merge_requests",
                description: "Merge requests of a project, recently updated first: iid, title, state, author, branches, conflicts and latest pipeline status.",
                inputSchema: JSONSchema.object([
                    "instance": instance,
                    "project": project,
                    "state": JSONSchema.string("Which merge requests to list; opened by default.", values: Self.mergeRequestStates),
                    "author": JSONSchema.string("Only merge requests by this username."),
                    "limit": JSONSchema.integer("How many merge requests to return.", minimum: 1, maximum: 100, default: 20)
                ], required: ["project"]),
                annotations: readOnly
            ),
            Tool(
                name: "gitlab_merge_request",
                description: """
                One merge request: title, description, branches, author, state, conflicts, latest pipeline and the \
                changed files with added and removed line counts. The whole diff is never returned; pass file to get \
                the diff of one changed file.
                """,
                inputSchema: JSONSchema.object([
                    "instance": instance,
                    "project": project,
                    "iid": JSONSchema.identifier("Merge request number within the project, as in /-/merge_requests/<iid>."),
                    "file": JSONSchema.string("Path of one changed file to show its diff.")
                ], required: ["project", "iid"]),
                annotations: readOnly
            )
        ]
    }

    func call(_ name: String, arguments values: [String: Value], credentials: [MCPCredential]) async -> MCPToolOutput {
        let arguments = ToolArguments(values: values)
        do {
            switch name {
            case "gitlab_instances":
                return .success(instances(credentials))
            case "gitlab_resolve_url":
                return try await resolve(arguments.requiredString("url"), credentials: credentials)
            case "gitlab_pipelines":
                let client = try makeClient(for: arguments, credentials)
                return .success(try await pipelines(
                    client,
                    project: arguments.requiredString("project"),
                    ref: arguments.string("ref"),
                    status: arguments.string("status"),
                    limit: arguments.int("limit", default: 10, in: 1...50)
                ))
            case "gitlab_pipeline":
                let client = try makeClient(for: arguments, credentials)
                return .success(try await pipeline(
                    client,
                    project: arguments.requiredString("project"),
                    id: arguments.requiredInt("pipeline_id")
                ))
            case "gitlab_job_log":
                let client = try makeClient(for: arguments, credentials)
                return try await jobLog(
                    client,
                    project: arguments.requiredString("project"),
                    jobID: arguments.requiredInt("job_id"),
                    tail: arguments.int("tail", default: JobLog.defaultTail, in: 1...JobLog.maxTail),
                    grep: arguments.string("grep"),
                    context: arguments.int("context", default: JobLog.defaultContext, in: 0...JobLog.maxContext)
                )
            case "gitlab_merge_requests":
                let client = try makeClient(for: arguments, credentials)
                return .success(try await mergeRequests(
                    client,
                    project: arguments.requiredString("project"),
                    state: arguments.string("state") ?? "opened",
                    author: arguments.string("author"),
                    limit: arguments.int("limit", default: 20, in: 1...100)
                ))
            case "gitlab_merge_request":
                let client = try makeClient(for: arguments, credentials)
                return try await mergeRequest(
                    client,
                    project: arguments.requiredString("project"),
                    iid: arguments.requiredInt("iid"),
                    file: arguments.string("file")
                )
            default:
                return .failure("Toolbelt has no tool named \(name).")
            }
        } catch {
            return .failure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: Instances

    private func instances(_ credentials: [MCPCredential]) -> String {
        let enabled = credentials.filter { $0.token != nil }
        guard !enabled.isEmpty else { return "No GitLab instance is turned on in Toolbelt." }

        var lines = ["GitLab instances enabled in Toolbelt — \(enabled.count):"]
        for credential in enabled {
            let resource = credential.resource
            var parts = [resource.name, resource.host, resource.baseURL.absoluteString]
            if let account = resource.account {
                parts.append("user @\(account.username)")
                switch account.expiry {
                case let .on(date) where account.isExpired():
                    parts.append("token expired \(Self.day(date))")
                case let .on(date):
                    parts.append("token expires \(Self.day(date))")
                case .never:
                    parts.append("token never expires")
                case .unknown:
                    break
                }
            }
            lines.append(parts.joined(separator: " · "))
        }
        let disabled = credentials.count - enabled.count
        if disabled > 0 { lines.append("\(disabled) more turned off by the user.") }
        return lines.joined(separator: "\n")
    }

    private func makeClient(for arguments: ToolArguments, _ credentials: [MCPCredential]) throws -> GitLabClient {
        let enabled = credentials.filter { $0.token != nil }

        guard let wanted = arguments.string("instance") else {
            if enabled.count == 1 { return try makeClient(enabled[0]) }
            if enabled.isEmpty { throw MCPToolError("No GitLab instance is turned on in Toolbelt.") }
            throw MCPToolError("Several GitLab instances are enabled, so pass instance: one of \(Self.names(enabled)).")
        }
        guard let match = credentials.first(where: { Self.matches($0.resource, wanted) }) else {
            throw MCPToolError("Toolbelt has no GitLab instance “\(wanted)”. Enabled: \(Self.names(enabled)).")
        }
        return try makeClient(match)
    }

    private func makeClient(_ credential: MCPCredential) throws -> GitLabClient {
        guard let token = credential.token else {
            throw MCPToolError("The GitLab instance “\(credential.resource.name)” is turned off in Toolbelt.")
        }
        return makeClient(baseURL: credential.resource.baseURL, token: token)
    }

    private func makeClient(baseURL: URL, token: String) -> GitLabClient {
        GitLabClient(baseURL: baseURL, token: token, session: session)
    }

    private static func matches(_ resource: MCPResource, _ wanted: String) -> Bool {
        var value = wanted.lowercased()
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) {
            value.removeFirst(scheme.count)
        }
        while value.hasSuffix("/") { value.removeLast() }

        let base = resource.baseURL.absoluteString.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return value == resource.name.lowercased()
            || value == resource.host.lowercased()
            || value == resource.baseURL.host(percentEncoded: false)?.lowercased()
            || value == base
    }

    private static func names(_ credentials: [MCPCredential]) -> String {
        guard !credentials.isEmpty else { return "none" }
        return credentials.map { "\($0.resource.name) (\($0.resource.host))" }.joined(separator: ", ")
    }

    // MARK: Links

    private func resolve(_ link: String, credentials: [MCPCredential]) async throws -> MCPToolOutput {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = GitLabLinkParser.host(of: url)
        else { throw MCPToolError("“\(link)” is not a link.") }

        let path = url.path(percentEncoded: false)
        let candidates = credentials
            .filter { $0.resource.host.lowercased() == host }
            .filter { path.hasPrefix(Self.basePath(of: $0.resource)) }
            .sorted { Self.basePath(of: $0.resource).count > Self.basePath(of: $1.resource).count }
        guard let credential = candidates.first(where: { $0.token != nil }) ?? candidates.first else {
            throw MCPToolError("No GitLab instance in Toolbelt is at \(host). The user can add it in Toolbelt → MCP.")
        }
        let client = try makeClient(credential)

        guard let target = GitLabLinkParser.parse(url, basePath: Self.basePath(of: credential.resource)) else {
            throw MCPToolError("The link has no project, pipeline, job, merge request or commit in it.")
        }

        let instance = credential.resource.name
        let project = target.projectPath
        func resolved(_ call: String) -> String {
            "Resolved as \(call) on instance “\(instance)”.\n\n"
        }

        switch target.target {
        case let .pipeline(id):
            let text = try await pipeline(client, project: project, id: id)
            return .success(resolved("gitlab_pipeline(project: \"\(project)\", pipeline_id: \(id))") + text)
        case let .job(id):
            let output = try await jobLog(
                client, project: project, jobID: id,
                tail: JobLog.defaultTail, grep: nil, context: JobLog.defaultContext,
                prefix: resolved("gitlab_job_log(project: \"\(project)\", job_id: \(id))")
            )
            return output
        case let .mergeRequest(iid):
            return try await mergeRequest(
                client, project: project, iid: iid, file: nil,
                prefix: resolved("gitlab_merge_request(project: \"\(project)\", iid: \(iid))")
            )
        case let .commit(sha):
            let text = try await commit(client, project: project, sha: sha)
            return .success(resolved("a commit lookup in \(project)") + text)
        case .project:
            let text = try await pipelines(client, project: project, ref: nil, status: nil, limit: 10)
            return .success(resolved("gitlab_pipelines(project: \"\(project)\")") + text)
        }
    }

    private static func basePath(of resource: MCPResource) -> String {
        var path = resource.baseURL.path(percentEncoded: false)
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    // MARK: Pipelines

    private func pipelines(
        _ client: GitLabClient,
        project: String,
        ref: String?,
        status: String?,
        limit: Int
    ) async throws -> String {
        if let status, !Self.pipelineStatuses.contains(status) {
            throw MCPToolError("Unknown status “\(status)”. Use one of: \(Self.pipelineStatuses.joined(separator: ", ")).")
        }
        let segment = GitLabClient.projectSegment(project)
        let page: GitLabPage<GitLabPipeline> = try await client.page(
            "projects/\(segment)/pipelines",
            query: ["order_by": "id", "sort": "desc", "ref": ref, "status": status],
            page: 1,
            perPage: limit
        )

        // The list has no author and no duration; those come with each pipeline's own record.
        let detailed = await withTaskGroup(of: (Int, GitLabPipeline?).self) { group in
            for (index, pipeline) in page.items.enumerated() {
                group.addTask {
                    (index, try? await client.get("projects/\(segment)/pipelines/\(pipeline.id)", as: GitLabPipeline.self))
                }
            }
            var result = page.items
            for await (index, pipeline) in group {
                if let pipeline { result[index] = pipeline }
            }
            return result
        }

        var filters: [String] = []
        if let ref { filters.append("ref \(ref)") }
        if let status { filters.append("status \(status)") }
        return formatter.pipelines(detailed, project: project, filters: filters)
    }

    private func pipeline(_ client: GitLabClient, project: String, id: Int) async throws -> String {
        let segment = GitLabClient.projectSegment(project)
        let pipeline: GitLabPipeline = try await client.get("projects/\(segment)/pipelines/\(id)")

        async let jobs = client.all("projects/\(segment)/pipelines/\(id)/jobs", of: GitLabJob.self)
        async let bridges = client.all("projects/\(segment)/pipelines/\(id)/bridges", of: GitLabBridge.self)
        async let commit = commitIfExists(client, segment: segment, sha: pipeline.sha)

        let jobList = try await jobs
        let bridgeList = try await bridges
        return formatter.pipeline(
            pipeline,
            project: project,
            commit: await commit,
            jobs: jobList.items,
            bridges: bridgeList.items,
            isComplete: jobList.isComplete && bridgeList.isComplete
        )
    }

    private func commitIfExists(_ client: GitLabClient, segment: String, sha: String?) async -> GitLabCommit? {
        guard let sha else { return nil }
        return try? await client.get("projects/\(segment)/repository/commits/\(GitLabClient.encodeSegment(sha))")
    }

    private func commit(_ client: GitLabClient, project: String, sha: String) async throws -> String {
        let segment = GitLabClient.projectSegment(project)
        let commit: GitLabCommit = try await client.get(
            "projects/\(segment)/repository/commits/\(GitLabClient.encodeSegment(sha))"
        )
        let pipelines: GitLabPage<GitLabPipeline> = try await client.page(
            "projects/\(segment)/pipelines",
            query: ["sha": commit.id, "order_by": "id", "sort": "desc"],
            page: 1,
            perPage: 10
        )
        return formatter.commit(commit, project: project, pipelines: pipelines.items)
    }

    // MARK: Jobs

    private func jobLog(
        _ client: GitLabClient,
        project: String,
        jobID: Int,
        tail: Int,
        grep: String?,
        context: Int,
        prefix: String = ""
    ) async throws -> MCPToolOutput {
        let segment = GitLabClient.projectSegment(project)
        async let job: GitLabJob = client.get("projects/\(segment)/jobs/\(jobID)")
        async let trace = traceIfExists(client, segment: segment, jobID: jobID)

        let header = formatter.jobHeader(try await job)
        let lines = JobLog.cleanLines(try await trace)

        let section: (header: String, body: String)
        let keep: MCPText.Keep
        if let grep {
            section = try JobLog.grep(lines, pattern: grep, context: context)
            keep = .head
        } else if lines.isEmpty {
            section = ("The log is empty: the job has not written anything yet.", "")
            keep = .tail
        } else {
            section = JobLog.tail(lines, count: tail)
            keep = .tail
        }

        let top = prefix + header + "\n\n" + section.header + (section.body.isEmpty ? "" : "\n")
        let body = MCPText.limited(section.body, limit: max(1_000, MCPText.responseLimit - top.count), keep: keep)
        return MCPToolOutput(text: top + body, isError: false)
    }

    private func traceIfExists(_ client: GitLabClient, segment: String, jobID: Int) async throws -> String {
        do {
            return try await client.text("projects/\(segment)/jobs/\(jobID)/trace")
        } catch GitLabError.notFound {
            return ""
        }
    }

    // MARK: Merge requests

    private func mergeRequests(
        _ client: GitLabClient,
        project: String,
        state: String,
        author: String?,
        limit: Int
    ) async throws -> String {
        guard Self.mergeRequestStates.contains(state) else {
            throw MCPToolError("Unknown state “\(state)”. Use one of: \(Self.mergeRequestStates.joined(separator: ", ")).")
        }
        let segment = GitLabClient.projectSegment(project)
        let page: GitLabPage<GitLabMergeRequest> = try await client.page(
            "projects/\(segment)/merge_requests",
            query: ["state": state, "author_username": author, "order_by": "updated_at", "sort": "desc"],
            page: 1,
            perPage: limit
        )
        var filters = ["state \(state)"]
        if let author { filters.append("author \(author)") }
        return formatter.mergeRequests(page.items, project: project, filters: filters)
    }

    private func mergeRequest(
        _ client: GitLabClient,
        project: String,
        iid: Int,
        file: String?,
        prefix: String = ""
    ) async throws -> MCPToolOutput {
        let segment = GitLabClient.projectSegment(project)
        async let request: GitLabMergeRequest = client.get("projects/\(segment)/merge_requests/\(iid)")
        async let diffs = mergeRequestDiffs(client, segment: segment, iid: iid)

        let mergeRequest = try await request
        let changes = try await diffs

        guard let file else {
            let text = formatter.mergeRequest(mergeRequest, diffs: changes.items, isComplete: changes.isComplete)
            return .success(prefix + text)
        }

        guard let diff = Self.diff(for: file, in: changes.items) else {
            let paths = changes.items.prefix(30).map(\.newPath).joined(separator: "\n")
            throw MCPToolError("!\(iid) does not change “\(file)”. Changed files:\n\(paths.isEmpty ? "(none)" : paths)")
        }
        let section = formatter.fileDiff(diff, request: mergeRequest)
        let top = prefix + section.header + "\n\n"
        let body = MCPText.limited(section.body, limit: max(1_000, MCPText.responseLimit - top.count - 12), keep: .head)
        return MCPToolOutput(text: top + "```diff\n" + body + "\n```", isError: false)
    }

    private func mergeRequestDiffs(
        _ client: GitLabClient,
        segment: String,
        iid: Int
    ) async throws -> (items: [GitLabDiff], isComplete: Bool) {
        do {
            return try await client.all("projects/\(segment)/merge_requests/\(iid)/diffs", maxPages: 10, of: GitLabDiff.self)
        } catch GitLabError.notFound {
            // GitLab before 15.7 has only the older /changes endpoint.
            let changes: GitLabChanges = try await client.get("projects/\(segment)/merge_requests/\(iid)/changes")
            return (changes.changes, true)
        }
    }

    private static func diff(for file: String, in diffs: [GitLabDiff]) -> GitLabDiff? {
        var path = file.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") { path.removeFirst() }
        if let exact = diffs.first(where: { $0.newPath == path || $0.oldPath == path }) { return exact }
        let suffixed = diffs.filter { $0.newPath.hasSuffix("/" + path) || $0.oldPath.hasSuffix("/" + path) }
        return suffixed.count == 1 ? suffixed[0] : nil
    }

    private static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
