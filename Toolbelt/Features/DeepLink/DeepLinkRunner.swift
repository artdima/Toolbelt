//
//  DeepLinkRunner.swift
//  Toolbelt
//

import Foundation
import OSLog

/// Parsing tool output is kept apart from spawning processes: pure functions are
/// tested against real captured output.
enum DeepLinkParsing {
    static func simulators(fromSimctlJSON data: Data) -> [DeepLinkTarget] {
        SimulatorParsing.simulators(fromSimctlJSON: data)
            .filter { $0.state == .booted }
            .map { device in
                DeepLinkTarget(
                    platform: .ios,
                    identifier: device.identifier,
                    name: "\(device.name) · \(device.detail)"
                )
            }
    }

    static func androidDevices(fromAdbOutput output: String) -> [DeepLinkTarget] {
        output
            .split(separator: "\n")
            .dropFirst() // "List of devices attached"
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
}

protocol DeepLinkOpening {
    func targets() async -> (targets: [DeepLinkTarget], warning: String?)
    func open(url: String, on target: DeepLinkTarget) async -> DeepLinkResult
}

struct DeepLinkRunner: DeepLinkOpening {
    func targets() async -> (targets: [DeepLinkTarget], warning: String?) {
        // The two queries are independent and a cold simctl takes seconds — run them in parallel.
        async let simulators = bootedSimulators()
        async let android = connectedAndroidDevices()

        let simulatorTargets = await simulators
        let androidResult = await android
        return (simulatorTargets + androidResult.targets, androidResult.warning)
    }

    func open(url: String, on target: DeepLinkTarget) async -> DeepLinkResult {
        switch target.platform {
        case .ios:
            let arguments = ["simctl", "openurl", target.identifier, url]
            return await execute(ExecutablePath.xcrun, arguments) { $0.isSuccess }

        case .android:
            guard let adb = AndroidTools.resolvedPath() else {
                return DeepLinkResult(command: "", output: "adb not found", isSuccess: false)
            }
            let arguments = [
                "-s", target.identifier,
                "shell", "am", "start",
                "-a", "android.intent.action.VIEW",
                "-d", Shell.singleQuoted(url)
            ]
            // `am start` returns 0 even when no activity was found.
            return await execute(adb, arguments) { result in
                let output = result.combinedOutput
                return result.isSuccess
                    && !output.contains("Error:")
                    && !output.contains("Exception")
            }
        }
    }

    private func execute(
        _ executable: String,
        _ arguments: [String],
        isSuccess: (ShellResult) -> Bool
    ) async -> DeepLinkResult {
        let command = Shell.displayCommand(executable, arguments)
        do {
            let result = try await Shell.run(executable, arguments)
            return DeepLinkResult(
                command: command,
                output: result.combinedOutput,
                isSuccess: isSuccess(result)
            )
        } catch {
            return DeepLinkResult(
                command: command,
                output: error.localizedDescription,
                isSuccess: false
            )
        }
    }

    private func bootedSimulators() async -> [DeepLinkTarget] {
        do {
            let result = try await Shell.run(
                ExecutablePath.xcrun,
                ["simctl", "list", "devices", "booted", "-j"]
            )
            guard result.isSuccess else { return [] }
            return DeepLinkParsing.simulators(fromSimctlJSON: Data(result.standardOutput.utf8))
        } catch {
            Log.shell.error("simctl is unavailable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func connectedAndroidDevices() async -> (targets: [DeepLinkTarget], warning: String?) {
        guard let adb = AndroidTools.resolvedPath() else {
            let warning = AndroidTools.customPath.isEmpty
                ? "adb not found — set the path in Settings → Tools"
                : "adb not found at the path from Settings"
            return ([], warning)
        }

        do {
            let result = try await Shell.run(adb, ["devices", "-l"])
            guard result.isSuccess else {
                return ([], "adb returned an error: \(result.combinedOutput)")
            }
            return (DeepLinkParsing.androidDevices(fromAdbOutput: result.standardOutput), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }
}
