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

    static func simulators(fromSimctlJSON data: Data) -> [SimulatorDevice] {
        guard let list = try? JSONDecoder().decode(SimctlList.self, from: data) else { return [] }

        return list.devices
            .sorted { $0.key < $1.key }
            .flatMap { pair in
                pair.value
                    .filter { $0.isAvailable ?? true }
                    .map { device in
                        SimulatorDevice(
                            platform: .ios,
                            identifier: device.udid,
                            name: device.name,
                            detail: runtimeTitle(pair.key),
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

    static func runtimeTitle(_ identifier: String) -> String {
        let name = identifier.replacingOccurrences(
            of: "com.apple.CoreSimulator.SimRuntime.",
            with: ""
        )
        let parts = name.split(separator: "-").map(String.init)
        guard let platform = parts.first else { return name }

        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? platform : "\(platform) \(version)"
    }

    /// `emulator -list-avds` prints one name per line and mixes in INFO and WARNING
    /// lines; an AVD name never contains whitespace.
    static func avdNames(fromEmulatorOutput output: String) -> [String] {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(where: \.isWhitespace) }
    }

    static func runningEmulatorSerials(fromAdbOutput output: String) -> [String] {
        output
            .split(separator: "\n")
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
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" }
    }

    static func lastLines(_ text: String, limit: Int = 8) -> String {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(limit)
            .joined(separator: "\n")
    }
}
