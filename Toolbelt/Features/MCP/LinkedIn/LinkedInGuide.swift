//
//  LinkedInGuide.swift
//  Toolbelt
//
//  Setting up a LinkedIn resource, for the Setup Guide window.
//

import Foundation

nonisolated enum LinkedInGuide {
    static let developerApps = URL(string: "https://www.linkedin.com/developers/apps")!
    static let tokenGenerator = URL(string: "https://www.linkedin.com/developers/tools/oauth/token-generator")!
    static let scopes = ["openid", "profile", "email", "w_member_social"]

    static func guide(dailyPostLimit: Int) -> MCPGuide {
        MCPGuide(
            summary: """
            Claude sees whose account it is and, once you turn on Allow write, publishes and deletes text posts \
            as you. Only through LinkedIn's official API, with an app of your own.
            """,
            steps: [
                MCPGuide.Step(
                    title: "Create a LinkedIn app",
                    text: """
                    On LinkedIn Developers press **Create app**. LinkedIn ties every app to a LinkedIn Page: a \
                    basic page you admin will do.
                    """,
                    link: MCPGuide.WebLink(title: "Open LinkedIn Developers", url: developerApps)
                ),
                MCPGuide.Step(
                    title: "Add two products",
                    text: """
                    On the app's **Products** tab add **Sign In with LinkedIn using OpenID Connect** and \
                    **Share on LinkedIn**. The first tells Toolbelt whose token it is, the second lets it post.
                    """
                ),
                MCPGuide.Step(
                    title: "Copy Client ID and Client Secret",
                    text: "Both are on the app's **Auth** tab. Toolbelt uses them to check the token's scopes and expiry date."
                ),
                MCPGuide.Step(
                    title: "Generate an access token",
                    text: """
                    In **OAuth Token Generator** pick the app, tick the scopes below and sign in. Copy the access \
                    token: it lasts 60 days.
                    """,
                    link: MCPGuide.WebLink(title: "Open OAuth Token Generator", url: tokenGenerator),
                    values: scopes
                ),
                MCPGuide.Step(
                    title: "Add the resource",
                    text: """
                    In the MCP window press **Add Resource**, choose **LinkedIn** and fill in **Client ID**, \
                    **Client Secret** and **Access Token**. **Check** shows the member, the scopes and the expiry \
                    date; **Save** stores the secret and the token in Keychain only.
                    """
                ),
                MCPGuide.Step(
                    title: "Allow write, if Claude should post",
                    text: """
                    Without it Claude only sees whose account it is and the posts published through Toolbelt. \
                    Turn on **Allow write** next to the resource and confirm: Claude can then publish and delete \
                    posts as you.
                    """
                ),
                .connectClaude
            ],
            examples: [
                "Whose LinkedIn account is connected?",
                "Write a post about our release and show it to me before publishing.",
                "Delete the post you published an hour ago."
            ],
            notes: [
                "The token stops working after 60 days: generate a new one the same way and paste it with Edit.",
                "Every post is either public or for connections only, and Claude has to say which.",
                "Toolbelt publishes at most \(dailyPostLimit) posts a day per resource.",
                "LinkedIn does not let the app read your feed, so Claude knows only the posts it published through Toolbelt."
            ]
        )
    }
}
