//
//  ReleaseNotesGenerator.swift
//  Toolbelt
//

import Foundation

protocol ReleaseNotesGenerating {
    func paragraph(
        from changes: String,
        language: ReleaseNotesLanguage,
        in repository: String
    ) async throws -> String
}

struct ClaudeReleaseNotesGenerator: ReleaseNotesGenerating {
    private static let timeout: TimeInterval = 120

    func paragraph(
        from changes: String,
        language: ReleaseNotesLanguage,
        in repository: String
    ) async throws -> String {
        guard let claude = ClaudeCLI.resolvedPath() else {
            throw ClaudeCLIError.notFound
        }

        let environment = ClaudeCLI.environment(for: claude, base: await LoginShellEnvironment.resolved())
        let result = try await Shell.run(
            claude,
            [
                "-p", ReleaseNotesBuilder.claudePrompt(for: changes, language: language),
                "--output-format", "text",
                "--no-session-persistence",
                // Commit subjects are someone else's text: without tools they can only steer the wording.
                "--disallowedTools", "*"
            ],
            timeout: Self.timeout,
            environment: environment,
            workingDirectory: repository
        )

        guard result.isSuccess else {
            let message = result.combinedOutput
            throw ClaudeCLIError.failed(message.isEmpty ? "claude exited with code \(result.exitCode)" : message)
        }

        let paragraph = ReleaseNotesBuilder.paragraph(from: result.standardOutput)
        guard !paragraph.isEmpty else {
            throw ClaudeCLIError.emptyResponse
        }
        return paragraph
    }
}
