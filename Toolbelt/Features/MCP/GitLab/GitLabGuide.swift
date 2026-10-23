//
//  GitLabGuide.swift
//  Toolbelt
//
//  Setting up a GitLab resource: the Setup Guide and the token page the editor links to.
//

import Foundation

nonisolated enum GitLabGuide {
    static let tokenScope = "read_api"

    /// Opens with the name and the scope already filled in; an instance served under a prefix keeps it.
    static func tokenPage(for baseURL: URL) -> URL? {
        URL(string: baseURL.absoluteString + "/-/user_settings/personal_access_tokens?name=Toolbelt&scopes=\(tokenScope)")
    }

    static func guide(for baseURL: URL?) -> MCPGuide {
        let host = baseURL.flatMap(GitLabLinkParser.host(of:)) ?? "your GitLab"
        let tokenLink = baseURL.flatMap(tokenPage(for:)).map { MCPGuide.WebLink(title: "Open Access Tokens on \(host)", url: $0) }
        let pipelineLink = (baseURL?.absoluteString ?? "https://gitlab.com") + "/mobile/app/-/pipelines/123456"

        return MCPGuide(
            summary: """
            Claude reads pipelines with all their jobs, job logs and merge requests with their changes, on \
            gitlab.com or your company's own GitLab. It is read-only: Claude cannot retry a job, comment or merge.
            """,
            steps: [
                MCPGuide.Step(
                    title: "Create a token",
                    text: """
                    On your GitLab open **User Settings → Access Tokens** and add a legacy personal access token \
                    with only the **read_api** scope. The link below opens that page with the name and the scope \
                    filled in: pick an expiry date and press **Create token**. GitLab shows the token once, so \
                    copy it right away.
                    """,
                    link: tokenLink,
                    values: [tokenScope]
                ),
                MCPGuide.Step(
                    title: "Add the resource",
                    text: """
                    In the MCP window press **Add Resource** and choose **GitLab**. **Address** is where GitLab \
                    opens in the browser: https://gitlab.com or, say, https://gitlab.company.com. **Name** is how \
                    you and Claude tell instances apart, e.g. work. Paste the token into **Token**.
                    """
                ),
                MCPGuide.Step(
                    title: "Check and save",
                    text: """
                    **Check** asks GitLab whose token it is and shows its scopes and expiry date. **Save** stores \
                    the token in Keychain only.
                    """
                ),
                .connectClaude
            ],
            examples: [
                "Why did the last pipeline on main in mobile/app fail?",
                "What broke here? \(pipelineLink)",
                "Show my open merge requests in mobile/app and their pipelines.",
                "Find “error:” in the log of the failed job."
            ],
            notes: [
                "403 in an answer means the token has no read_api scope or no access to that project.",
                "Several instances can live side by side: add each one with its own name and token.",
                "A token that expires within \(MCPAccount.expiryWarningDays) days is marked in the MCP window. Create a new one and paste it with Edit.",
                "Turning the resource off takes its tools away from Claude at once."
            ]
        )
    }
}
