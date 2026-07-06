//
//  DeepLinkModels.swift
//  Toolbelt
//

import Foundation

enum DeepLinkPlatform: String, Hashable {
    case ios
    case android

    var title: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}

struct DeepLinkTarget: Identifiable, Hashable {
    let platform: DeepLinkPlatform
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
