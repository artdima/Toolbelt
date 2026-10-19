//
//  ClaudeConfig.swift
//  Toolbelt
//
//  Registering toolbelt-mcp with Claude Desktop and Claude Code.
//

import Foundation

nonisolated enum ClaudeConfigError: LocalizedError, Equatable {
    case claudeNotInstalled
    case notAnObject
    case serversNotAnObject
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            return "Claude Desktop does not seem to be installed: there is no ~/Library/Application Support/Claude"
        case .notAnObject:
            return "claude_desktop_config.json is not a JSON object, so it was left as it is"
        case .serversNotAnObject:
            return "“mcpServers” in claude_desktop_config.json is not an object, so the file was left as it is"
        case let .unreadable(reason):
            return "Could not read claude_desktop_config.json: \(reason)"
        }
    }
}

nonisolated enum ClaudeDesktopConfig {
    static let serverName = "toolbelt"

    enum Status: Equatable {
        case notInstalled
        case notConnected
        case connected
        /// The entry points at another copy of the helper, e.g. a build from Xcode.
        case otherPath(String)
        case unreadable(String)
    }

    struct InstallResult: Equatable {
        let backupURL: URL?
        let wasAlreadyConnected: Bool
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/claude_desktop_config.json")
    }

    static func status(helperPath: String, configURL: URL = defaultURL) -> Status {
        let directory = configURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return .notInstalled
        }
        guard let data = try? Data(contentsOf: configURL) else { return .notConnected }

        do {
            let servers = try mcpServers(in: try object(from: data))
            guard let entry = servers[serverName] as? [String: Any] else { return .notConnected }
            let command = entry["command"] as? String ?? ""
            return command == helperPath ? .connected : .otherPath(command)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// Other servers and keys are kept as they are; an existing entry only gets the new path.
    static func merged(_ data: Data?, helperPath: String) throws -> Data {
        var root: [String: Any] = [:]
        if let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            root = try object(from: data)
        }

        var servers = try mcpServers(in: root)
        var entry = servers[serverName] as? [String: Any] ?? [:]
        entry["command"] = helperPath
        servers[serverName] = entry
        root["mcpServers"] = servers

        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    static func install(helperPath: String, configURL: URL = defaultURL, now: Date = Date()) throws -> InstallResult {
        let fileManager = FileManager.default
        let directory = configURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            throw ClaudeConfigError.claudeNotInstalled
        }

        var existing: Data?
        if fileManager.fileExists(atPath: configURL.path(percentEncoded: false)) {
            do {
                existing = try Data(contentsOf: configURL)
            } catch {
                throw ClaudeConfigError.unreadable(error.localizedDescription)
            }
        }

        if case .connected = status(helperPath: helperPath, configURL: configURL) {
            return InstallResult(backupURL: nil, wasAlreadyConnected: true)
        }

        let updated = try merged(existing, helperPath: helperPath)

        var backupURL: URL?
        if let existing {
            let backup = directory.appending(path: "\(configURL.lastPathComponent).backup-\(backupStamp(now))")
            try existing.write(to: backup, options: .atomic)
            backupURL = backup
        }
        try updated.write(to: configURL, options: .atomic)
        return InstallResult(backupURL: backupURL, wasAlreadyConnected: false)
    }

    private static func object(from data: Data) throws -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClaudeConfigError.unreadable("it is not valid JSON")
        }
        guard let object = value as? [String: Any] else { throw ClaudeConfigError.notAnObject }
        return object
    }

    private static func mcpServers(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["mcpServers"] else { return [:] }
        guard let servers = value as? [String: Any] else { throw ClaudeConfigError.serversNotAnObject }
        return servers
    }

    private static func backupStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04ld%02ld%02ld-%02ld%02ld%02ld",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }
}

nonisolated enum ClaudeCodeCommand {
    static func add(helperPath: String) -> String {
        "claude mcp add --scope user \(ClaudeDesktopConfig.serverName) -- \(shellQuoted(helperPath))"
    }

    static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:@%")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
