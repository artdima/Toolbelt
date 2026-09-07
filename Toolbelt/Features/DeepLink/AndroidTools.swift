//
//  AndroidTools.swift
//  Toolbelt
//

import Foundation

enum AndroidToolsError: LocalizedError, Equatable {
    case notExecutable(String)
    case untrustedLocation(String)

    var errorDescription: String? {
        switch self {
        case let .notExecutable(path):
            return "There is no executable at \(path)"
        case let .untrustedLocation(path):
            return "\(path) is outside the directories where adb is expected"
        }
    }
}

/// Locating adb. The path comes from settings, otherwise from the usual places:
/// a menu bar app has neither Homebrew nor the Android SDK on its PATH.
enum AndroidTools {
    static let pathKey = "adb.path"

    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The path is executed as is, and UserDefaults is writable by any process running
    /// as the user. The directories are restricted so that a tampered plist cannot turn
    /// into arbitrary code execution under a signed app.
    private static var trustedPrefixes: [String] {
        ["/usr/", "/opt/", "/Applications/", "\(home)/Library/Android/", "\(home)/Android/"]
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
        // Validated on read too: the value could have reached the plist behind the app's back.
        return (try? validate(custom)) == nil ? nil : custom
    }

    static func autodetectedPath() -> String? {
        var candidates = [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/Android/Sdk/platform-tools/adb"
        ]

        let environment = ProcessInfo.processInfo.environment
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.insert("\(root)/platform-tools/adb", at: 0)
            }
        }

        return candidates.first { path in
            FileManager.default.isExecutableFile(atPath: path) && (try? validate(path)) != nil
        }
    }

    @discardableResult
    private static func validate(_ path: String) throws -> String {
        guard trustedPrefixes.contains(where: path.hasPrefix) else {
            throw AndroidToolsError.untrustedLocation(path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw AndroidToolsError.notExecutable(path)
        }
        return path
    }
}
