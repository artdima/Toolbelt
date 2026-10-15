//
//  IssuesBoard.swift
//  Toolbelt
//
//  Laying issues out into status columns. Pure logic, computed once after a load
//  or a query change rather than on every redraw.
//

import Foundation

struct IssuesBoard: Equatable {
    struct Column: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let name: String
        let issues: [Issue]

        var stage: Stage { IssuesBoard.stage(ofStatus: key) }
    }

    /// Where a status sits in the process; the board marks each column with it.
    enum Stage: Equatable {
        case waiting
        case active
        case review
        case testing
        case done
    }

    /// Known statuses follow the order of the process, the rest go after them alphabetically.
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

    static func stage(ofStatus key: String) -> Stage {
        switch key {
        case "inProgress", "inDevelopment", "development": return .active
        case "readyForReview", "review", "codeReview": return .review
        case "readyForTest", "testing", "acceptance": return .testing
        case "readyForRelease", "released", "resolved", "closed": return .done
        default: return .waiting
        }
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
