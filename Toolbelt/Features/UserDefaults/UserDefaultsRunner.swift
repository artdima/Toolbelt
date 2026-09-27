//
//  UserDefaultsRunner.swift
//  Toolbelt
//

import Foundation
import OSLog

protocol UserDefaultsControlling {
    /// Booted simulators only: `defaults` runs inside the device.
    func devices() async -> (devices: [SimulatorDevice], warning: String?)
    func apps(on device: SimulatorDevice) async -> (apps: [InstalledApp], warning: String?)
    func entries(of app: InstalledApp, on device: SimulatorDevice) async -> (entries: [UserDefaultsEntry], error: String?)
    func write(
        _ value: UserDefaultsValue,
        forKey key: String,
        of app: InstalledApp,
        on device: SimulatorDevice
    ) async -> UserDefaultsActionResult
    func delete(key: String, of app: InstalledApp, on device: SimulatorDevice) async -> UserDefaultsActionResult
    func reveal(_ app: InstalledApp) async
}

struct UserDefaultsRunner: UserDefaultsControlling {
    func devices() async -> (devices: [SimulatorDevice], warning: String?) {
        do {
            let result = try await Shell.run(
                ExecutablePath.xcrun,
                ["simctl", "list", "devices", "booted", "-j"]
            )
            guard result.isSuccess else {
                return ([], "simctl is unavailable: \(result.combinedOutput)")
            }
            return (SimulatorParsing.simulators(fromSimctlJSON: Data(result.standardOutput.utf8)), nil)
        } catch {
            Log.shell.error("simctl is unavailable: \(error.localizedDescription, privacy: .public)")
            return ([], error.localizedDescription)
        }
    }

    func apps(on device: SimulatorDevice) async -> (apps: [InstalledApp], warning: String?) {
        do {
            let result = try await Shell.run(ExecutablePath.xcrun, ["simctl", "listapps", device.identifier])
            guard result.isSuccess else {
                return ([], "simctl listapps failed: \(result.combinedOutput)")
            }
            return (UserDefaultsParsing.installedApps(fromListappsOutput: Data(result.standardOutput.utf8)), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    /// `defaults export` asks cfprefsd, so a value the app has just set is there before it
    /// reaches the disk. The plist on disk is the fallback.
    func entries(of app: InstalledApp, on device: SimulatorDevice) async -> (entries: [UserDefaultsEntry], error: String?) {
        let exported = try? await Shell.run(
            ExecutablePath.xcrun,
            ["simctl", "spawn", device.identifier, "defaults", "export", app.bundleID, "-"]
        )
        if let exported, exported.isSuccess,
           let entries = UserDefaultsParsing.entries(fromPlist: Data(exported.standardOutput.utf8)) {
            return (entries, nil)
        }

        // An app that has never stored anything has no domain and no plist; that is not an error.
        guard let path = app.preferencesPlistPath,
              let data = FileManager.default.contents(atPath: path)
        else { return ([], nil) }

        guard let entries = UserDefaultsParsing.entries(fromPlist: data) else {
            return ([], "Could not read \(path)")
        }
        return (entries, nil)
    }

    func write(
        _ value: UserDefaultsValue,
        forKey key: String,
        of app: InstalledApp,
        on device: SimulatorDevice
    ) async -> UserDefaultsActionResult {
        guard let typed = value.writeArguments else {
            return UserDefaultsActionResult(
                command: "",
                output: "A \(value.typeName) value cannot be written with defaults",
                isSuccess: false
            )
        }
        return await execute(["simctl", "spawn", device.identifier, "defaults", "write", app.bundleID, key] + typed)
    }

    func delete(key: String, of app: InstalledApp, on device: SimulatorDevice) async -> UserDefaultsActionResult {
        await execute(["simctl", "spawn", device.identifier, "defaults", "delete", app.bundleID, key])
    }

    /// Selects the plist in Finder, or opens the Preferences folder while there is no plist yet.
    func reveal(_ app: InstalledApp) async {
        guard let path = app.preferencesPlistPath else { return }

        let folder = (path as NSString).deletingLastPathComponent
        let arguments = FileManager.default.fileExists(atPath: path) ? ["-R", path] : [folder]
        _ = try? await Shell.run(ExecutablePath.open, arguments, timeout: 15)
    }

    private func execute(_ arguments: [String]) async -> UserDefaultsActionResult {
        let command = Shell.displayCommand(ExecutablePath.xcrun, arguments)
        do {
            let result = try await Shell.run(ExecutablePath.xcrun, arguments)
            return UserDefaultsActionResult(
                command: command,
                output: result.combinedOutput,
                isSuccess: result.isSuccess
            )
        } catch {
            return UserDefaultsActionResult(
                command: command,
                output: error.localizedDescription,
                isSuccess: false
            )
        }
    }
}
