//
//  ClaudeCLI.swift
//  Toolbelt
//

import Foundation

enum ClaudeCLIError: LocalizedError, Equatable {
    case notFound
    case notExecutable(String)
    case untrustedLocation(String)
    case failed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude CLI not found — set the path in Settings → Tools"
        case let .notExecutable(path):
            return "There is no executable at \(path)"
        case let .untrustedLocation(path):
            return "\(path) is outside the directories where claude is expected"
        case let .failed(message):
            guard message.localizedCaseInsensitiveContains("authenticate") else { return message }
            return "\(message) — run claude in Terminal and sign in with /login"
        case .emptyResponse:
            return "Claude returned an empty response"
        }
    }
}

/// Locating claude the same way as adb: a path from settings, otherwise the usual install locations.
enum ClaudeCLI {
    static let pathKey = "claude.path"

    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The path comes from a user-writable plist, so the directories are restricted as for adb.
    private static var trustedPrefixes: [String] {
        [
            "/usr/", "/opt/", "/Applications/",
            "\(home)/.local/", "\(home)/.claude/", "\(home)/.npm-global/", "\(home)/.nvm/", "\(home)/.bun/"
        ]
    }

    static var customPath: String {
        UserDefaults.standard.string(forKey: pathKey) ?? ""
    }

    static func setCustomPath(_ path: String) throws {
        guard !path.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pathKey)
            return
        }

        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        try validate(standardized)
        UserDefaults.standard.set(standardized, forKey: pathKey)
    }

    static func resolvedPath() -> String? {
        let custom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !custom.isEmpty else { return autodetectedPath() }
        return (try? validate(custom)) == nil ? nil : custom
    }

    static func autodetectedPath() -> String? {
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude"
        ]

        return candidates.first { path in
            FileManager.default.isExecutableFile(atPath: path) && (try? validate(path)) != nil
        }
    }

    /// An npm install is a `#!/usr/bin/env node` script, so node has to be reachable next to claude.
    static func environment(for executable: String, base: [String: String]) -> [String: String] {
        var environment = base
        let directory = (executable as NSString).deletingLastPathComponent
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [directory, "/opt/homebrew/bin", "/usr/local/bin", inherited]
            .joined(separator: ":")
        return environment
    }

    @discardableResult
    private static func validate(_ path: String) throws -> String {
        guard trustedPrefixes.contains(where: path.hasPrefix) else {
            throw ClaudeCLIError.untrustedLocation(path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw ClaudeCLIError.notExecutable(path)
        }
        return path
    }
}
