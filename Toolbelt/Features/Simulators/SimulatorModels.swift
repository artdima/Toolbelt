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
    /// The runtime for iOS, the AVD identifier for Android.
    let detail: String
    var state: SimulatorState
    /// The adb serial of a running emulator, the handle `emu kill` needs.
    var serial: String?

    var id: String { "\(platform.rawValue):\(identifier)" }
}

struct SimulatorActionResult: Equatable {
    let command: String
    let output: String
    let isSuccess: Bool
}
