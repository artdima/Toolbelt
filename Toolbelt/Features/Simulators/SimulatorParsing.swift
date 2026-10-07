//
//  SimulatorParsing.swift
//  Toolbelt
//

import Foundation

/// The single place that reads simctl, emulator and adb output. Pure functions,
/// tested against real captured output.
enum SimulatorParsing {
    private struct SimctlList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let isAvailable: Bool?
        }

        let devices: [String: [Device]]
    }

    /// Only iOS runtimes: simctl also answers for watchOS, tvOS and visionOS.
    static func simulators(fromSimctlJSON data: Data) -> [SimulatorDevice] {
        guard let list = try? JSONDecoder().decode(SimctlList.self, from: data) else { return [] }

        return list.devices
            .sorted { $0.key < $1.key }
            .flatMap { pair -> [SimulatorDevice] in
                let os = runtime(pair.key)
                guard os.platform == MobilePlatform.ios.title else { return [] }

                return pair.value
                    .filter { $0.isAvailable ?? true }
                    .map { device in
                        SimulatorDevice(
                            platform: .ios,
                            identifier: device.udid,
                            name: device.name,
                            osVersion: os.version,
                            state: state(fromSimctl: device.state),
                            serial: nil
                        )
                    }
            }
    }

    static func state(fromSimctl value: String) -> SimulatorState {
        switch value.lowercased() {
        case "booted": return .booted
        case "booting": return .booting
        default: return .shutdown
        }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-18-0` is the iOS 18.0 runtime.
    static func runtime(_ identifier: String) -> (platform: String, version: String) {
        let name = identifier.replacingOccurrences(
            of: "com.apple.CoreSimulator.SimRuntime.",
            with: ""
        )
        let parts = name.split(separator: "-").map(String.init)
        return (parts.first ?? name, parts.dropFirst().joined(separator: "."))
    }

    /// An AVD's `<name>.ini` names its target, `target=android-34`; its config.ini names
    /// the system image, `image.sysdir.1=system-images/android-34/google_apis/arm64-v8a/`.
    static func androidAPILevel(fromAvdIni text: String) -> String? {
        let prefix = "android-"

        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)

            let target: String?
            switch key {
            case "target":
                target = value
            case "image.sysdir.1":
                target = value.split(separator: "/").map(String.init).first { $0.hasPrefix(prefix) }
            default:
                continue
            }

            if let target, target.hasPrefix(prefix) {
                return String(target.dropFirst(prefix.count))
            }
        }
        return nil
    }

    /// `emulator -list-avds` prints one name per line and mixes in INFO and WARNING
    /// lines; an AVD name never contains whitespace.
    static func avdNames(fromEmulatorOutput output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(where: \.isWhitespace) }
    }

    static func runningEmulatorSerials(fromAdbOutput output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 2,
                      fields[0].hasPrefix("emulator-"),
                      fields[1] == "device"
                else { return nil }
                return fields[0]
            }
    }

    /// `adb emu avd name` answers with the name and a trailing OK.
    static func avdName(fromEmuOutput output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" }
    }

    static func lastLines(_ text: String, limit: Int = 8) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(limit)
            .joined(separator: "\n")
    }
}
