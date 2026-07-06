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
            return "По пути \(path) нет исполняемого файла"
        case let .untrustedLocation(path):
            return "Путь \(path) вне каталогов, где ожидается adb"
        }
    }
}

/// Поиск adb. Путь берётся из настроек, иначе из типовых мест: у приложения
/// из строки меню в PATH нет ни Homebrew, ни Android SDK.
enum AndroidTools {
    static let pathKey = "adb.path"

    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Путь исполняется как есть, а UserDefaults доступны на запись любому процессу
    /// пользователя. Каталоги ограничены, чтобы подменённый plist не превращался
    /// в запуск произвольного кода от имени подписанного приложения.
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
        // Проверяем и на чтении: значение могло попасть в plist в обход приложения.
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
