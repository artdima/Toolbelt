//
//  SimulatorModels.swift
//  Toolbelt
//

import Foundation

enum SimulatorState: String, Hashable {
    case shutdown
    case booting
    case booted

    var title: String {
        switch self {
        case .shutdown: return "Shutdown"
        case .booting: return "Booting"
        case .booted: return "Booted"
        }
    }
}

struct SimulatorDevice: Identifiable, Hashable {
    let platform: MobilePlatform
    /// A simulator udid or an AVD name.
    let identifier: String
    let name: String
    /// "18.0" for iOS, "API 34" for Android; empty when unknown.
    let osVersion: String
    var state: SimulatorState
    /// The adb serial of a running emulator, the handle `emu kill` needs.
    var serial: String?

    var id: String { Self.id(platform: platform, identifier: identifier) }

    static func id(platform: MobilePlatform, identifier: String) -> String {
        "\(platform.rawValue):\(identifier)"
    }
}

/// Devices of one platform on the same OS version, the way the window lists them.
struct SimulatorGroup: Identifiable, Equatable {
    let platform: MobilePlatform
    let osVersion: String
    let devices: [SimulatorDevice]

    var id: String { "\(platform.rawValue):\(osVersion)" }
    var title: String { osVersion.isEmpty ? platform.title : "\(platform.title) \(osVersion)" }

    /// iOS before Android, newest version first, devices in the order the SDK lists them.
    static func grouped(_ devices: [SimulatorDevice]) -> [SimulatorGroup] {
        MobilePlatform.allCases.flatMap { platform -> [SimulatorGroup] in
            Dictionary(grouping: devices.filter { $0.platform == platform }, by: \.osVersion)
                .sorted { isNewer($0.key, than: $1.key) }
                .map { SimulatorGroup(platform: platform, osVersion: $0.key, devices: $0.value) }
        }
    }

    /// The whole group when its title matches, otherwise the devices whose name does.
    func matching(_ query: String) -> SimulatorGroup? {
        guard !title.lowercased().contains(query) else { return self }

        let matches = devices.filter { $0.name.lowercased().contains(query) }
        return matches.isEmpty ? nil : SimulatorGroup(platform: platform, osVersion: osVersion, devices: matches)
    }

    /// A version without digits is a preview codename or nothing at all: those go after
    /// the numbered ones, and an empty version last.
    private static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = numbers(in: lhs)
        let right = numbers(in: rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return left.isEmpty == right.isEmpty ? rhs < lhs : right.isEmpty
        }
        return right.lexicographicallyPrecedes(left)
    }

    private static func numbers(in version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}

/// What a cheap poll can tell about a device without enumerating everything again.
struct SimulatorStatus: Equatable {
    let state: SimulatorState
    let serial: String?
}

struct SimulatorActionResult: Equatable {
    let command: String
    let output: String
    let isSuccess: Bool
}
