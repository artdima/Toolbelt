//
//  SimulatorRunner.swift
//  Toolbelt
//

import Foundation
import OSLog

protocol SimulatorControlling {
    func devices() async -> (devices: [SimulatorDevice], warning: String?)
    /// Everything a booting device changes, without enumerating the whole SDK again.
    func statuses() async -> [SimulatorDevice.ID: SimulatorStatus]
    func boot(_ device: SimulatorDevice) async -> SimulatorActionResult
    func shutdown(_ device: SimulatorDevice) async -> SimulatorActionResult
}

struct SimulatorRunner: SimulatorControlling {
    /// A broken AVD or a system image of the wrong architecture dies at once.
    private static let launchGracePeriod: TimeInterval = 3
    /// A cold simctl reads every runtime on disk and takes seconds.
    private static let listTimeout: TimeInterval = 60

    private struct RunningEmulator {
        let serial: String
        let isBooted: Bool
    }

    func devices() async -> (devices: [SimulatorDevice], warning: String?) {
        async let simulators = iosSimulators()
        async let emulators = androidEmulators()

        let ios = await simulators
        let android = await emulators
        let warnings = [ios.warning, android.warning].compactMap { $0 }

        return (
            ios.devices + android.devices,
            warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        )
    }

    func statuses() async -> [SimulatorDevice.ID: SimulatorStatus] {
        async let simulators = bootedSimulatorIdentifiers()
        async let emulators = runningEmulators()

        var statuses: [SimulatorDevice.ID: SimulatorStatus] = [:]

        for udid in await simulators {
            let id = SimulatorDevice.id(platform: .ios, identifier: udid)
            statuses[id] = SimulatorStatus(state: .booted, serial: nil)
        }

        for (name, emulator) in await emulators {
            let id = SimulatorDevice.id(platform: .android, identifier: name)
            statuses[id] = SimulatorStatus(
                state: emulator.isBooted ? .booted : .booting,
                serial: emulator.serial
            )
        }

        return statuses
    }

    func boot(_ device: SimulatorDevice) async -> SimulatorActionResult {
        switch device.platform {
        case .ios: return await bootSimulator(device)
        case .android: return await bootEmulator(device)
        }
    }

    func shutdown(_ device: SimulatorDevice) async -> SimulatorActionResult {
        switch device.platform {
        case .ios:
            return await execute(ExecutablePath.xcrun, ["simctl", "shutdown", device.identifier]) { result, output in
                result.isSuccess || output.contains("current state: Shutdown")
            }

        case .android:
            guard let adb = AndroidTools.resolvedPath(), let serial = device.serial else {
                return SimulatorActionResult(
                    command: "",
                    output: "The emulator is not visible to adb",
                    isSuccess: false
                )
            }
            return await execute(adb, ["-s", serial, "emu", "kill"]) { result, _ in result.isSuccess }
        }
    }

    private func bootSimulator(_ device: SimulatorDevice) async -> SimulatorActionResult {
        // simctl refuses to boot what is already booted; for the user that is not a failure.
        let booted = await execute(ExecutablePath.xcrun, ["simctl", "boot", device.identifier]) { result, output in
            result.isSuccess || output.contains("current state: Booted")
        }
        guard booted.isSuccess else { return booted }

        // simctl boots headless: without this the simulator runs with no window.
        _ = try? await Shell.run(ExecutablePath.open, ["-a", "Simulator"], timeout: 15)
        return booted
    }

    private func bootEmulator(_ device: SimulatorDevice) async -> SimulatorActionResult {
        guard let emulator = AndroidTools.resolvedEmulatorPath() else {
            return SimulatorActionResult(
                command: "",
                output: "The Android emulator was not found next to adb",
                isSuccess: false
            )
        }

        let arguments = ["-avd", device.identifier]
        let command = Shell.displayCommand(emulator, arguments)
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolbelt-emulator-\(device.identifier).log")

        do {
            // The emulator resolves its own libraries relative to its directory.
            let failure = try await Shell.launch(
                emulator,
                arguments,
                environment: await LoginShellEnvironment.resolved(),
                workingDirectory: (emulator as NSString).deletingLastPathComponent,
                logFile: log,
                gracePeriod: Self.launchGracePeriod
            )
            guard let failure else {
                return SimulatorActionResult(command: command, output: "", isSuccess: true)
            }

            let reason = SimulatorParsing.lastLines(failure.combinedOutput)
            return SimulatorActionResult(
                command: command,
                output: reason.isEmpty ? "The emulator exited with code \(failure.exitCode)" : reason,
                isSuccess: false
            )
        } catch {
            return SimulatorActionResult(
                command: command,
                output: error.localizedDescription,
                isSuccess: false
            )
        }
    }

    private func execute(
        _ executable: String,
        _ arguments: [String],
        isSuccess: (ShellResult, String) -> Bool
    ) async -> SimulatorActionResult {
        let command = Shell.displayCommand(executable, arguments)
        do {
            let result = try await Shell.run(executable, arguments)
            let output = result.combinedOutput
            return SimulatorActionResult(
                command: command,
                output: output,
                isSuccess: isSuccess(result, output)
            )
        } catch {
            return SimulatorActionResult(
                command: command,
                output: error.localizedDescription,
                isSuccess: false
            )
        }
    }

    private func iosSimulators() async -> (devices: [SimulatorDevice], warning: String?) {
        do {
            let result = try await Shell.run(
                ExecutablePath.xcrun,
                ["simctl", "list", "devices", "available", "-j"],
                timeout: Self.listTimeout
            )
            // Command Line Tools without Xcode: there is no simctl to ask.
            guard result.isSuccess else {
                return ([], "simctl is unavailable: \(result.combinedOutput)")
            }

            // simctl also answers for watchOS, tvOS and visionOS; this window is about phones.
            let devices = SimulatorParsing
                .simulators(fromSimctlJSON: Data(result.standardOutput.utf8))
                .filter { $0.detail.hasPrefix(MobilePlatform.ios.title) }
            return (devices, nil)
        } catch {
            Log.shell.error("simctl is unavailable: \(error.localizedDescription, privacy: .public)")
            return ([], error.localizedDescription)
        }
    }

    private func bootedSimulatorIdentifiers() async -> [String] {
        guard let result = try? await Shell.run(
            ExecutablePath.xcrun,
            ["simctl", "list", "devices", "booted", "-j"]
        ), result.isSuccess else { return [] }

        return SimulatorParsing
            .simulators(fromSimctlJSON: Data(result.standardOutput.utf8))
            .map(\.identifier)
    }

    private func androidEmulators() async -> (devices: [SimulatorDevice], warning: String?) {
        guard let emulator = AndroidTools.resolvedEmulatorPath() else {
            let warning = AndroidTools.customPath.isEmpty
                ? "The Android emulator was not found — set the path to adb in Settings → Tools"
                : "The Android emulator was not found next to the adb from Settings"
            return ([], warning)
        }

        let names: [String]
        do {
            // The same environment the emulator is launched with: ANDROID_AVD_HOME decides
            // which AVDs exist at all, and it only lives in the login shell.
            let result = try await Shell.run(
                emulator,
                ["-list-avds"],
                timeout: Self.listTimeout,
                environment: await LoginShellEnvironment.resolved()
            )
            guard result.isSuccess else {
                return ([], "emulator returned an error: \(result.combinedOutput)")
            }
            names = SimulatorParsing.avdNames(fromEmulatorOutput: result.standardOutput)
        } catch {
            return ([], error.localizedDescription)
        }

        let running = await runningEmulators()
        return (names.map { device(avd: $0, running: running[$0]) }, nil)
    }

    private func device(avd name: String, running: RunningEmulator?) -> SimulatorDevice {
        let state: SimulatorState
        if let running {
            state = running.isBooted ? .booted : .booting
        } else {
            state = .shutdown
        }

        return SimulatorDevice(
            platform: .android,
            identifier: name,
            name: name,
            detail: "",
            state: state,
            serial: running?.serial
        )
    }

    /// adb knows a running emulator by its serial; the AVD it was started from has to be
    /// asked for separately.
    private func runningEmulators() async -> [String: RunningEmulator] {
        guard let adb = AndroidTools.resolvedPath(),
              let list = try? await Shell.run(adb, ["devices"]),
              list.isSuccess
        else { return [:] }

        var running: [String: RunningEmulator] = [:]
        for serial in SimulatorParsing.runningEmulatorSerials(fromAdbOutput: list.standardOutput) {
            guard let answer = try? await Shell.run(adb, ["-s", serial, "emu", "avd", "name"], timeout: 10),
                  let name = SimulatorParsing.avdName(fromEmuOutput: answer.standardOutput)
            else { continue }

            let completed = try? await Shell.run(
                adb,
                ["-s", serial, "shell", "getprop", "sys.boot_completed"],
                timeout: 10
            )
            running[name] = RunningEmulator(
                serial: serial,
                isBooted: completed?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            )
        }
        return running
    }
}
