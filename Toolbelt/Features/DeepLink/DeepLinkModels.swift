//
//  DeepLinkModels.swift
//  Toolbelt
//

import Foundation

struct DeepLinkTarget: Identifiable, Hashable {
    let platform: MobilePlatform
    let identifier: String
    let name: String
    /// "iOS 18.0" for a simulator, the adb serial for an Android device.
    var detail = ""

    var id: String { "\(platform.rawValue):\(identifier)" }
    var title: String { detail.isEmpty ? name : "\(name) · \(detail)" }
}

struct DeepLinkResult: Equatable {
    let command: String
    let output: String
    let isSuccess: Bool
}

struct DeepLinkEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: String
    var isPinned = false
    /// Where and when the link was last opened; nil in history saved by older versions.
    var deviceName: String?
    var openedAt: Date?
}
