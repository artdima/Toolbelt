//
//  ReleaseNotesModels.swift
//  Toolbelt
//

import Foundation

enum NoteLocale: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru: return "Russian"
        case .en: return "English"
        }
    }
}

enum StoreTarget: String, CaseIterable, Identifiable {
    case appStore
    case googlePlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appStore: return "App Store"
        case .googlePlay: return "Google Play"
        }
    }

    /// Store limits on the What's New text.
    var characterLimit: Int {
        switch self {
        case .appStore: return 4000
        case .googlePlay: return 500
        }
    }
}

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

    func title(_ locale: NoteLocale) -> String {
        switch (self, locale) {
        case (.breaking, .ru): return "Важно"
        case (.breaking, .en): return "Important"
        case (.feature, .ru): return "Новое"
        case (.feature, .en): return "What's new"
        case (.fix, .ru): return "Исправления"
        case (.fix, .en): return "Fixes"
        case (.performance, .ru): return "Оптимизация"
        case (.performance, .en): return "Performance"
        case (.other, .ru): return "Прочее"
        case (.other, .en): return "Other"
        }
    }
}
