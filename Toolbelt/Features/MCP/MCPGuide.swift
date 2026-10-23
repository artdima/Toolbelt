//
//  MCPGuide.swift
//  Toolbelt
//
//  How to set up a kind of resource, for the Setup Guide window.
//

import Foundation

nonisolated struct MCPGuide: Sendable {
    nonisolated struct WebLink: Sendable, Equatable {
        let title: String
        let url: URL
    }

    nonisolated struct Step: Sendable, Identifiable {
        let title: String
        /// Markdown: bold for buttons and fields, so they read as they look in the window.
        let text: String
        var link: WebLink?
        var values: [String] = []

        var id: String { title }

        static let connectClaude = Step(
            title: "Connect Claude",
            text: """
            Once per Mac, not per resource. In the MCP window press **Connect to Claude Desktop**, then quit it \
            with ⌘Q and open it again. For Claude Code press **Copy Command** and run it in Terminal. Clients \
            that are already connected are told about the new tools; start a new chat if they do not show up.
            """
        )
    }

    let summary: String
    let steps: [Step]
    let examples: [String]
    let notes: [String]
}
