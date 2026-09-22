//
//  DeepLinkModels.swift
//  Toolbelt
//

import Foundation

struct DeepLinkTarget: Identifiable, Hashable {
    let platform: MobilePlatform
    let identifier: String
    let name: String

    var id: String { "\(platform.rawValue):\(identifier)" }
    var title: String { "\(platform.title) · \(name)" }
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
}
