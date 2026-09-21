//
//  ReleaseNotesModels.swift
//  Toolbelt
//

import Foundation

struct ReleaseCommit: Equatable {
    let type: String?
    let isBreaking: Bool
    let summary: String
}

enum ReleaseSection: CaseIterable {
    case breaking
    case feature
    case fix
    case performance
    case other
}

/// Store locales the What's New text can be written in. The raw value is what
/// ends up in UserDefaults, so renaming a case resets the saved choice.
enum ReleaseNotesLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case russian
    case german
    case french
    case spanish
    case portugueseBR
    case italian
    case turkish
    case chineseSimplified
    case japanese
    case korean

    var id: String { rawValue }

    /// A saved choice that no longer matches a case falls back to English.
    static func restored(from rawValue: String?) -> ReleaseNotesLanguage {
        rawValue.flatMap(ReleaseNotesLanguage.init(rawValue:)) ?? .english
    }

    var title: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .german: "German"
        case .french: "French"
        case .spanish: "Spanish"
        case .portugueseBR: "Portuguese"
        case .italian: "Italian"
        case .turkish: "Turkish"
        case .chineseSimplified: "Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        }
    }

    /// The name the prompt uses. Listed case by case on purpose: a new language has to
    /// spell out how the model should be asked for it, not inherit the picker label.
    var promptName: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .german: "German"
        case .french: "French"
        case .spanish: "Spanish"
        case .portugueseBR: "Brazilian Portuguese"
        case .italian: "Italian"
        case .turkish: "Turkish"
        case .chineseSimplified: "Simplified Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        }
    }
}
