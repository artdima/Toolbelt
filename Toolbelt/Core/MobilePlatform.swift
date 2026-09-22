//
//  MobilePlatform.swift
//  Toolbelt
//

import Foundation

enum MobilePlatform: String, Hashable, CaseIterable {
    case ios
    case android

    var title: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}
