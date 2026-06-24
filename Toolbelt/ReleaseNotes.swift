//
//  ReleaseNotes.swift
//  Toolbelt
//
//  Черновик What's New для App Store и Google Play из коммитов репозитория.
//

import SwiftUI

// MARK: - Площадки и локали

enum NoteLocale: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru: return "Русский"
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

    /// Лимиты площадок на текст «Что нового».
    var limit: Int {
        switch self {
        case .appStore: return 4000
        case .googlePlay: return 500
        }
    }
}

// MARK: - Разбор коммитов

struct ReleaseCommit {
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

enum ReleaseNotesBuilder {
    private static let technicalTypes: Set<String> = [
        "chore", "refactor", "docs", "test", "tests", "ci", "build", "style"
    ]

    /// Формат Conventional Commits: `type(scope)!: описание`.
    /// Всё, что под него не подходит, попадает в «Прочее» целиком.
    static func parse(subject: String) -> ReleaseCommit {
        guard let colon = headerColon(in: subject) else {
            return ReleaseCommit(type: nil, isBreaking: false, summary: subject)
        }

        var prefix = String(subject[subject.startIndex..<colon])
        let rest = String(subject[subject.index(after: colon)...])
            .trimmingCharacters(in: .whitespaces)

        let isBreaking = prefix.hasSuffix("!")
        if isBreaking {
            prefix.removeLast()
        }
        if let paren = prefix.firstIndex(of: "(") {
            prefix = String(prefix[prefix.startIndex..<paren])
        }

        let looksLikeType = !prefix.isEmpty && prefix.allSatisfy { $0.isLetter && $0.isLowercase }
        guard looksLikeType, !rest.isEmpty else {
            return ReleaseCommit(type: nil, isBreaking: false, summary: subject)
        }

        return ReleaseCommit(type: prefix, isBreaking: isBreaking, summary: rest)
    }

    /// Двоеточие заголовка — первое вне скобок и до первого пробела:
    /// в `fix(api:v2): текст` двоеточие внутри scope заголовок не заканчивает.
    private static func headerColon(in subject: String) -> String.Index? {
        var depth = 0
        var index = subject.startIndex

        while index < subject.endIndex {
            let character = subject[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 && character == ":" {
                return index
            } else if depth == 0 && character == " " {
                return nil
            }
            index = subject.index(after: index)
        }

        return nil
    }

    static func section(for commit: ReleaseCommit) -> ReleaseSection {
        if commit.isBreaking { return .breaking }
        switch commit.type {
        case "feat": return .feature
        case "fix": return .fix
        case "perf": return .performance
        default: return .other
        }
    }

    static func isTechnical(_ commit: ReleaseCommit) -> Bool {
        guard !commit.isBreaking, let type = commit.type else { return false }
        return technicalTypes.contains(type)
    }

    static func commits(from subjects: [String], includeTechnical: Bool) -> [ReleaseCommit] {
        subjects
            .map { parse(subject: $0) }
            .filter { includeTechnical || !isTechnical($0) }
    }

    static func draft(
        commits: [ReleaseCommit],
        locale: NoteLocale,
        store: StoreTarget
    ) -> String {
        var grouped: [ReleaseSection: [String]] = [:]
        for commit in commits {
            let line = "• " + capitalized(commit.summary)
            grouped[section(for: commit), default: []].append(line)
        }

        switch store {
        case .appStore:
            return ReleaseSection.allCases
                .compactMap { section in
                    guard let lines = grouped[section], !lines.isEmpty else { return nil }
                    return ([section.title(locale)] + lines).joined(separator: "\n")
                }
                .joined(separator: "\n\n")

        case .googlePlay:
            // 500 символов — заголовки разделов тут только съедают лимит.
            return ReleaseSection.allCases
                .flatMap { grouped[$0] ?? [] }
                .joined(separator: "\n")
        }
    }

    private static func capitalized(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }
}

// MARK: - Доступ к репозиторию

enum GitRepository {
    private static let git = "/usr/bin/git"
    static let pathKey = "releaseNotes.repositoryPath"

    static var lastPath: String {
        get { UserDefaults.standard.string(forKey: pathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: pathKey) }
    }

    static func isRepository(_ path: String) async -> Bool {
        let result = await Shell.run(git, ["-C", path, "rev-parse", "--is-inside-work-tree"])
        return result.code == 0
    }

    static func tags(at path: String) async -> [String] {
        let result = await Shell.run(git, ["-C", path, "tag", "--sort=-creatordate"])
        guard result.code == 0 else { return [] }
        return result.out
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func subjects(at path: String, from: String?, to: String) async -> (subjects: [String], error: String?) {
        let range = from.map { "\($0)..\(to)" } ?? to
        let result = await Shell.run(
            git,
            ["-C", path, "log", "--no-merges", "--pretty=format:%s", range, "--"]
        )

        guard result.code == 0 else {
            let message = result.err.trimmingCharacters(in: .whitespacesAndNewlines)
            return ([], message.isEmpty ? "git завершился с кодом \(result.code)" : message)
        }

        let subjects = result.out
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return (subjects, nil)
    }
}
