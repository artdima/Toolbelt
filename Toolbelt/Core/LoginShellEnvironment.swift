//
//  LoginShellEnvironment.swift
//  Toolbelt
//

import Foundation
import OSLog

/// A menu bar app is started by launchd and never sees what ~/.zshrc exports: PATH,
/// proxies, CLAUDE_CONFIG_DIR. The user's shell is asked once and the answer is cached.
nonisolated enum LoginShellEnvironment {
    static let marker = "__TOOLBELT_ENV__"

    private static let cache = Locked<[String: String]?>(nil)
    private static let timeout: TimeInterval = 10

    static func resolved() async -> [String: String] {
        if let cached = cache.withLock({ $0 }) {
            return cached
        }

        let fallback = ProcessInfo.processInfo.environment
        let result = try? await Shell.run(
            shellPath(fallback["SHELL"]),
            ["-l", "-i", "-c", "printf '%s' \(marker); /usr/bin/env -0"],
            timeout: timeout
        )
        guard let result, result.isSuccess, let parsed = parse(result.standardOutput) else {
            Log.shell.error("Could not read the login shell environment, using the app's own")
            return fallback
        }

        cache.withLock { $0 = parsed }
        return parsed
    }

    /// Everything before the marker is whatever the rc files print on startup.
    static func parse(_ output: String) -> [String: String]? {
        guard let start = output.range(of: marker, options: .backwards) else { return nil }

        var environment: [String: String] = [:]
        for entry in output[start.upperBound...].split(separator: "\0") {
            guard let equals = entry.firstIndex(of: "="), equals != entry.startIndex else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return environment.isEmpty ? nil : environment
    }

    static func shellPath(_ candidate: String?) -> String {
        guard let candidate,
              ["/bin/", "/usr/bin/", "/usr/local/bin/", "/opt/homebrew/bin/"].contains(where: candidate.hasPrefix),
              FileManager.default.isExecutableFile(atPath: candidate)
        else { return "/bin/zsh" }
        return candidate
    }
}
