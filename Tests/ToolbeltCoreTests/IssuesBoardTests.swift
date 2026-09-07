import Foundation
import Testing
@testable import ToolbeltCore

/// Testing exports an Issue type too — without qualifying it the name is ambiguous.
private typealias Issue = ToolbeltCore.Issue

@Suite("Issues board")
struct IssuesBoardTests {
    private func issue(_ key: String, summary: String = "Issue", status: String, statusName: String? = nil) -> Issue {
        Issue(
            key: key,
            summary: summary,
            statusKey: status,
            statusName: statusName ?? status,
            priorityKey: "normal",
            priorityName: "",
            queueName: "QUEUE",
            updatedAt: nil,
            deadline: nil
        )
    }

    @Test("An empty list yields an empty board")
    func emptyBoard() {
        let board = IssuesBoard(issues: [], searchQuery: "")

        #expect(board.isEmpty)
        #expect(board.issueCount == 0)
    }

    @Test("Issues are grouped by status")
    func issuesAreGroupedByStatus() {
        let board = IssuesBoard(
            issues: [
                issue("A-1", status: "open"),
                issue("A-2", status: "open"),
                issue("A-3", status: "closed")
            ],
            searchQuery: ""
        )

        #expect(board.columns.count == 2)
        #expect(board.columns.first { $0.key == "open" }?.issues.count == 2)
    }

    /// Column order follows the process, not the alphabet.
    @Test("Known statuses follow the process order")
    func knownStatusesFollowProcessOrder() {
        let board = IssuesBoard(
            issues: [
                issue("A-1", status: "closed"),
                issue("A-2", status: "inProgress"),
                issue("A-3", status: "open")
            ],
            searchQuery: ""
        )

        #expect(board.columns.map(\.key) == ["open", "inProgress", "closed"])
    }

    @Test("Unknown statuses go last, alphabetically")
    func unknownStatusesGoLastAlphabetically() {
        let board = IssuesBoard(
            issues: [
                issue("A-1", status: "zeta", statusName: "Zeta"),
                issue("A-2", status: "alpha", statusName: "Alpha"),
                issue("A-3", status: "open")
            ],
            searchQuery: ""
        )

        #expect(board.columns.map(\.key) == ["open", "alpha", "zeta"])
    }

    @Test("Search by issue key")
    func searchByKey() {
        let board = IssuesBoard(
            issues: [issue("ABC-1", status: "open"), issue("XYZ-2", status: "open")],
            searchQuery: "abc"
        )

        #expect(board.issueCount == 1)
    }

    @Test("Search by summary is case insensitive")
    func searchBySummaryIsCaseInsensitive() {
        let board = IssuesBoard(
            issues: [
                issue("A-1", summary: "Fix the Login", status: "open"),
                issue("A-2", summary: "Report", status: "open")
            ],
            searchQuery: "login"
        )

        #expect(board.issueCount == 1)
    }

    @Test("A blank query is ignored")
    func blankQueryIsIgnored() {
        let board = IssuesBoard(issues: [issue("A-1", status: "open")], searchQuery: "   ")

        #expect(board.issueCount == 1)
    }

    @Test("A search with no matches yields an empty board")
    func searchWithNoMatches() {
        let board = IssuesBoard(issues: [issue("A-1", status: "open")], searchQuery: "no such thing")

        #expect(board.isEmpty)
    }
}

@Suite("Overdue issues")
struct IssueOverdueTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func issue(deadlineDay: Int?) -> Issue {
        Issue(
            key: "A-1",
            summary: "Issue",
            statusKey: "open",
            statusName: "Open",
            priorityKey: "normal",
            priorityName: "",
            queueName: "",
            updatedAt: nil,
            deadline: deadlineDay.map {
                calendar.date(from: DateComponents(year: 2026, month: 9, day: $0))!
            }
        )
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15))!
    }

    @Test("Without a deadline nothing is overdue")
    func noDeadline() {
        #expect(issue(deadlineDay: nil).isOverdue(now: now, calendar: calendar) == false)
    }

    @Test("Yesterday's deadline is overdue")
    func yesterdayIsOverdue() {
        #expect(issue(deadlineDay: 9).isOverdue(now: now, calendar: calendar))
    }

    /// A deadline today is not overdue yet — the comparison is against the start of the day.
    @Test("A deadline today is not overdue yet")
    func todayIsNotOverdue() {
        #expect(issue(deadlineDay: 10).isOverdue(now: now, calendar: calendar) == false)
    }

    @Test("A future deadline is not overdue")
    func futureIsNotOverdue() {
        #expect(issue(deadlineDay: 20).isOverdue(now: now, calendar: calendar) == false)
    }
}
