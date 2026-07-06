//
//  IssuesBoard.swift
//  Toolbelt
//
//  Раскладка задач по колонкам-статусам. Чистая логика, считается один раз
//  после загрузки или смены запроса, а не на каждой перерисовке.
//

import Foundation

struct IssuesBoard: Equatable {
    struct Column: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let name: String
        let issues: [Issue]
    }

    /// Известные статусы идут в логичном порядке процесса, остальные — следом по алфавиту.
    static let knownStatusOrder = [
        "open", "needInfo", "new", "backlog",
        "inProgress", "inDevelopment", "development",
        "readyForReview", "review", "codeReview",
        "readyForTest", "testing", "acceptance",
        "readyForRelease", "released", "resolved", "closed"
    ]

    let columns: [Column]
    let issueCount: Int

    var isEmpty: Bool { columns.isEmpty }

    static let empty = IssuesBoard(issues: [], searchQuery: "")

    init(issues: [Issue], searchQuery: String) {
        let matching = Self.filter(issues, by: searchQuery)
        issueCount = matching.count
        columns = Self.makeColumns(from: matching)
    }

    static func filter(_ issues: [Issue], by searchQuery: String) -> [Issue] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return issues }
        return issues.filter {
            $0.key.lowercased().contains(query) || $0.summary.lowercased().contains(query)
        }
    }

    private static func makeColumns(from issues: [Issue]) -> [Column] {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [Issue]] = [:]

        for issue in issues {
            if grouped[issue.statusKey] == nil {
                order.append(issue.statusKey)
                names[issue.statusKey] = issue.statusName
            }
            grouped[issue.statusKey, default: []].append(issue)
        }

        return order
            .map { Column(key: $0, name: names[$0] ?? $0, issues: grouped[$0] ?? []) }
            .sorted { left, right in
                let leftRank = knownStatusOrder.firstIndex(of: left.key) ?? Int.max
                let rightRank = knownStatusOrder.firstIndex(of: right.key) ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }
}
