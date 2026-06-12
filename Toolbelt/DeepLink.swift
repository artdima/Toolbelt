//
//  DeepLink.swift
//  Toolbelt
//
//  Открытие deep link на загруженном симуляторе iOS или подключённом Android-устройстве.
//

import Observation
import SwiftUI

// MARK: - Запуск команд

enum Shell {
    /// Task.detached обязателен: при NonisolatedNonsendingByDefault одна лишь
    /// пометка nonisolated наследует изоляцию вызывающего, и ожидание процесса
    /// осталось бы на главном потоке.
    nonisolated static func run(
        _ executable: String,
        _ arguments: [String]
    ) async -> (out: String, err: String, code: Int32) {
        await Task.detached {
            runSynchronously(executable, arguments)
        }.value
    }

    private nonisolated static func runSynchronously(
        _ executable: String,
        _ arguments: [String]
    ) -> (out: String, err: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    /// Аргумент для `adb shell`: команда собирается на устройстве заново,
    /// поэтому `&` и пробелы в ссылке нужно закрыть кавычками.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func display(_ executable: String, _ arguments: [String]) -> String {
        let special: Set<Character> = [" ", "&", "?", ";", "|", "<", ">", "(", ")", "$", "*"]
        return ([executable] + arguments)
            .map { argument in
                if argument.hasPrefix("'") || argument.contains(where: { special.contains($0) }) {
                    return "\"\(argument)\""
                }
                return argument
            }
            .joined(separator: " ")
    }
}

// MARK: - Устройства

enum DeepLinkPlatform: String, Hashable {
    case ios
    case android

    var title: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}

struct DeepLinkTarget: Identifiable, Hashable {
    let platform: DeepLinkPlatform
    let identifier: String
    let name: String

    var id: String { "\(platform.rawValue):\(identifier)" }
}

enum AndroidTools {
    static let pathKey = "adb.path"

    static var customPath: String {
        get { UserDefaults.standard.string(forKey: pathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: pathKey) }
    }

    /// Путь из настроек, иначе первый найденный из типовых мест —
    /// у приложения из строки меню в PATH обычно нет ни Homebrew, ни Android SDK.
    static func resolvedPath() -> String? {
        let manager = FileManager.default
        let custom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return manager.isExecutableFile(atPath: custom) ? custom : nil
        }
        return autodetectedPath()
    }

    static func autodetectedPath() -> String? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path
        let environment = ProcessInfo.processInfo.environment

        var candidates = [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/Android/Sdk/platform-tools/adb"
        ]
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.insert("\(root)/platform-tools/adb", at: 0)
            }
        }

        return candidates.first { manager.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Результат

struct DeepLinkResult {
    let command: String
    let output: String
    let exitCode: Int32

    var isSuccess: Bool { exitCode == 0 }
}

// MARK: - Запуск

enum DeepLinkRunner {
    private static let xcrun = "/usr/bin/xcrun"

    static func loadTargets() async -> (targets: [DeepLinkTarget], warning: String?) {
        var found = await bootedSimulators()
        var warning: String?

        if let adb = AndroidTools.resolvedPath() {
            found += await connectedAndroidDevices(adb: adb)
        } else {
            warning = AndroidTools.customPath.isEmpty
                ? "adb не найден — укажите путь в настройках, вкладка «Инструменты»"
                : "adb не найден по пути из настроек"
        }

        return (found, warning)
    }

    static func open(url: String, on target: DeepLinkTarget) async -> DeepLinkResult {
        switch target.platform {
        case .ios:
            let arguments = ["simctl", "openurl", target.identifier, url]
            let result = await Shell.run(xcrun, arguments)
            return DeepLinkResult(
                command: Shell.display(xcrun, arguments),
                output: combine(result),
                exitCode: result.code
            )

        case .android:
            guard let adb = AndroidTools.resolvedPath() else {
                return DeepLinkResult(command: "", output: "adb не найден", exitCode: -1)
            }
            let arguments = [
                "-s", target.identifier,
                "shell", "am", "start",
                "-a", "android.intent.action.VIEW",
                "-d", Shell.singleQuoted(url)
            ]
            let result = await Shell.run(adb, arguments)
            let output = combine(result)
            // `am start` возвращает 0 даже когда активность не нашлась.
            let failed = output.contains("Error:") || output.contains("Exception")
            return DeepLinkResult(
                command: Shell.display(adb, arguments),
                output: output,
                exitCode: failed ? 1 : result.code
            )
        }
    }

    // MARK: Списки устройств

    private struct SimctlList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
        }

        let devices: [String: [Device]]
    }

    private static func bootedSimulators() async -> [DeepLinkTarget] {
        let result = await Shell.run(xcrun, ["simctl", "list", "devices", "booted", "-j"])
        guard result.code == 0, let data = result.out.data(using: .utf8) else { return [] }
        guard let list = try? JSONDecoder().decode(SimctlList.self, from: data) else { return [] }

        return list.devices
            .sorted { $0.key < $1.key }
            .flatMap { pair in
                pair.value.map { device in
                    DeepLinkTarget(
                        platform: .ios,
                        identifier: device.udid,
                        name: "\(device.name) · \(runtimeTitle(pair.key))"
                    )
                }
            }
    }

    private static func connectedAndroidDevices(adb: String) async -> [DeepLinkTarget] {
        let result = await Shell.run(adb, ["devices", "-l"])
        guard result.code == 0 else { return [] }

        return result.out
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard fields.count >= 2, fields[1] == "device" else { return nil }

                let model = fields
                    .first { $0.hasPrefix("model:") }?
                    .replacingOccurrences(of: "model:", with: "")
                    .replacingOccurrences(of: "_", with: " ")

                return DeepLinkTarget(
                    platform: .android,
                    identifier: fields[0],
                    name: model.map { "\($0) · \(fields[0])" } ?? fields[0]
                )
            }
    }

    private static func runtimeTitle(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func combine(_ result: (out: String, err: String, code: Int32)) -> String {
        [result.out, result.err]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - История

struct DeepLinkEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var url: String
    var isPinned: Bool = false
}

@Observable
final class DeepLinkHistoryStore {
    static let shared = DeepLinkHistoryStore()

    private static let storageKey = "deeplink.history"
    private static let unpinnedLimit = 20

    private(set) var entries: [DeepLinkEntry]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        entries = data.flatMap { try? JSONDecoder().decode([DeepLinkEntry].self, from: $0) } ?? []
    }

    func record(_ url: String) {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.url == url }) {
            let existing = updated.remove(at: index)
            updated.insert(existing, at: 0)
        } else {
            updated.insert(DeepLinkEntry(url: url), at: 0)
        }

        var unpinned = 0
        updated = updated.filter { entry in
            guard !entry.isPinned else { return true }
            unpinned += 1
            return unpinned <= Self.unpinnedLimit
        }

        apply(updated)
    }

    func togglePin(_ entry: DeepLinkEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries
        updated[index].isPinned.toggle()
        apply(updated)
    }

    func remove(_ entry: DeepLinkEntry) {
        apply(entries.filter { $0.id != entry.id })
    }

    private func apply(_ newEntries: [DeepLinkEntry]) {
        entries = newEntries
        guard let data = try? JSONEncoder().encode(newEntries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
