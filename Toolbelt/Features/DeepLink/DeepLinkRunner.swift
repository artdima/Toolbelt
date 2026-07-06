//
//  DeepLinkRunner.swift
//  Toolbelt
//

import Foundation

/// Разбор вывода инструментов вынесен из запуска процессов: чистые функции
/// проверяются тестами на реальных примерах вывода.
enum DeepLinkParsing {
    private struct SimctlList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
        }

        let devices: [String: [Device]]
    }

    static func simulators(fromSimctlJSON data: Data) -> [DeepLinkTarget] {
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

    static func androidDevices(fromAdbOutput output: String) -> [DeepLinkTarget] {
        output
            .split(separator: "\n")
            .dropFirst() // «List of devices attached»
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

    static func runtimeTitle(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

protocol DeepLinkOpening {
    func targets() async -> (targets: [DeepLinkTarget], warning: String?)
    func open(url: String, on target: DeepLinkTarget) async -> DeepLinkResult
}

struct DeepLinkRunner: DeepLinkOpening {
    func targets() async -> (targets: [DeepLinkTarget], warning: String?) {
        // Запросы независимы, а холодный simctl отвечает секунды — идём параллельно.
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
                return DeepLinkResult(command: "", output: "adb не найден", isSuccess: false)
            }
            let arguments = [
                "-s", target.identifier,
                "shell", "am", "start",
                "-a", "android.intent.action.VIEW",
                "-d", Shell.singleQuoted(url)
            ]
            // `am start` возвращает 0 даже когда активность не нашлась.
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
            Log.shell.error("simctl недоступен: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func connectedAndroidDevices() async -> (targets: [DeepLinkTarget], warning: String?) {
        guard let adb = AndroidTools.resolvedPath() else {
            let warning = AndroidTools.customPath.isEmpty
                ? "adb не найден — укажите путь в настройках, вкладка «Инструменты»"
                : "adb не найден по пути из настроек"
            return ([], warning)
        }

        do {
            let result = try await Shell.run(adb, ["devices", "-l"])
            guard result.isSuccess else {
                return ([], "adb ответил ошибкой: \(result.combinedOutput)")
            }
            return (DeepLinkParsing.androidDevices(fromAdbOutput: result.standardOutput), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }
}
