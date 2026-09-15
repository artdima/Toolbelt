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
