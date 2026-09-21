//
//  ReleaseNotesBuilder.swift
//  Toolbelt
//
//  Parsing Conventional Commits and building the What's New text.
//

import Foundation

enum ReleaseNotesBuilder {
    /// Google Play caps What's New at 500 characters, the strictest of the stores.
    static let characterLimit = 500

    private static let technicalTypes: Set<String> = [
        "chore", "refactor", "docs", "test", "tests", "ci", "build", "style"
    ]

    /// Conventional Commits format: `type(scope)!: description`.
    /// Anything that does not match goes to "Other" verbatim.
    static func parse(subject: String) -> ReleaseCommit {
        guard let colon = headerColon(in: subject) else {
            return ReleaseCommit(type: nil, isBreaking: false, summary: subject)
        }

        var prefix = String(subject[subject.startIndex..<colon])
        let rest = String(subject[subject.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)

        let isBreaking = prefix.hasSuffix("!")
        if isBreaking {
            prefix.removeLast()
        }
        if let paren = prefix.firstIndex(of: "(") {
            prefix = String(prefix[prefix.startIndex..<paren])
        }

        let looksLikeType = !prefix.isEmpty && prefix.allSatisfy { $0.isLetter && $0.isLowercase }
        guard looksLikeType, !rest.isEmpty else {
            return ReleaseCommit(type: nil, isBreaking: false, summary: subject)
        }

        return ReleaseCommit(type: prefix, isBreaking: isBreaking, summary: rest)
    }

    /// The header colon is the first one outside parentheses and before any space:
    /// in `fix(api:v2): text` the colon inside the scope does not end the header,
    /// and `Add support for X: details` is not a conventional commit at all.
    private static func headerColon(in subject: String) -> String.Index? {
        var depth = 0
        var index = subject.startIndex

        while index < subject.endIndex {
            let character = subject[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 && character == ":" {
                return index
            } else if depth == 0 && character == " " {
                return nil
            }
            index = subject.index(after: index)
        }

        return nil
    }

    static func section(for commit: ReleaseCommit) -> ReleaseSection {
        if commit.isBreaking { return .breaking }
        switch commit.type {
        case "feat": return .feature
        case "fix": return .fix
        case "perf": return .performance
        default: return .other
        }
    }

    static func isTechnical(_ commit: ReleaseCommit) -> Bool {
        guard !commit.isBreaking, let type = commit.type else { return false }
        return technicalTypes.contains(type)
    }

    static func commits(from subjects: [String], includeTechnical: Bool) -> [ReleaseCommit] {
        subjects
            .map { parse(subject: $0) }
            .filter { includeTechnical || !isTechnical($0) }
    }

    static func draft(commits: [ReleaseCommit]) -> String {
        var grouped: [ReleaseSection: [String]] = [:]
        for commit in commits {
            grouped[section(for: commit), default: []].append("• " + commit.summary.capitalizedFirst)
        }

        return ReleaseSection.allCases
            .flatMap { grouped[$0] ?? [] }
            .joined(separator: "\n")
    }

    static func claudePrompt(for changes: String, language: ReleaseNotesLanguage) -> String {
        """
        Write the "What's New" text for a mobile app store release based on the changes below.

        Rules:
        - One paragraph of plain text in \(language.promptName): no lists, headings, markdown or quotes.
        - Speak to end users, not developers. Describe what got better in general, slightly vague terms.
        - Leave out internal names, libraries, APIs, ticket numbers and other technical details.
        - Group related changes instead of listing each one.
        - Stay under \(characterLimit) characters.
        - Reply with the paragraph only, written in \(language.promptName).

        Changes:
        \(changes)
        """
    }

    static func paragraph(from response: String) -> String {
        response
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
