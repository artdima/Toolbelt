import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Доска задач")
struct IssuesBoardTests {
    private func issue(_ key: String, summary: String = "Задача", status: String, statusName: String? = nil) -> Issue {
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

    @Test("Пустой список даёт пустую доску")
    func emptyBoard() {
        let board = IssuesBoard(issues: [], searchQuery: "")

        #expect(board.isEmpty)
        #expect(board.issueCount == 0)
    }

    @Test("Задачи группируются по статусу")
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

    /// Порядок колонок отражает процесс, а не алфавит.
    @Test("Известные статусы идут в порядке процесса")
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

    @Test("Неизвестные статусы уходят в конец по алфавиту")
    func unknownStatusesGoLastAlphabetically() {
        let board = IssuesBoard(
            issues: [
                issue("A-1", status: "zeta", statusName: "Зета"),
                issue("A-2", status: "alpha", statusName: "Альфа"),
                issue("A-3", status: "open")
            ],
            searchQuery: ""
        )

        #expect(board.columns.map(\.key) == ["open", "alpha", "zeta"])
    }

    @Test("Поиск по ключу задачи")
    func searchByKey() {
        let board = IssuesBoard(
            issues: [issue("ABC-1", status: "open"), issue("XYZ-2", status: "open")],
            searchQuery: "abc"
        )

        #expect(board.issueCount == 1)
    }

    @Test("Поиск по названию, регистр не важен")
    func searchBySummaryIsCaseInsensitive() {
        let board = IssuesBoard(
            issues: [
                issue("A-1", summary: "Починить Логин", status: "open"),
                issue("A-2", summary: "Отчёт", status: "open")
            ],
            searchQuery: "логин"
        )

        #expect(board.issueCount == 1)
    }

    @Test("Пробелы в запросе игнорируются")
    func blankQueryIsIgnored() {
        let board = IssuesBoard(issues: [issue("A-1", status: "open")], searchQuery: "   ")

        #expect(board.issueCount == 1)
    }

    @Test("Пустой результат поиска даёт пустую доску")
    func searchWithNoMatches() {
        let board = IssuesBoard(issues: [issue("A-1", status: "open")], searchQuery: "нет такого")

        #expect(board.isEmpty)
    }
}

@Suite("Просрочка задачи")
struct IssueOverdueTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func issue(deadlineDay: Int?) -> Issue {
        Issue(
            key: "A-1",
            summary: "Задача",
            statusKey: "open",
            statusName: "Открыта",
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

    @Test("Без дедлайна задача не просрочена")
    func noDeadline() {
        #expect(issue(deadlineDay: nil).isOverdue(now: now, calendar: calendar) == false)
    }

    @Test("Вчерашний дедлайн — просрочка")
    func yesterdayIsOverdue() {
        #expect(issue(deadlineDay: 9).isOverdue(now: now, calendar: calendar))
    }

    /// Дедлайн сегодня ещё не просрочен — сравнение идёт с началом дня.
    @Test("Сегодняшний дедлайн ещё не просрочен")
    func todayIsNotOverdue() {
        #expect(issue(deadlineDay: 10).isOverdue(now: now, calendar: calendar) == false)
    }

    @Test("Будущий дедлайн не просрочен")
    func futureIsNotOverdue() {
        #expect(issue(deadlineDay: 20).isOverdue(now: now, calendar: calendar) == false)
    }
}
