import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Отчёт за неделю")
struct WeekReportTests {
    /// UTC, чтобы тесты не зависели от часового пояса машины.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    /// Понедельник 7 сентября 2026 года.
    private var monday: Date { date(7, hour: 0) }

    private func worklog(
        id: Int,
        issue: String,
        day: Int,
        hour: Int = 12,
        seconds: TimeInterval
    ) -> Worklog {
        Worklog(
            id: id,
            issueKey: issue,
            issueTitle: "Задача \(issue)",
            comment: nil,
            start: date(day, hour: hour),
            seconds: seconds
        )
    }

    @Test("Пустой отчёт")
    func emptyReport() {
        let report = WeekReport(entries: [], weekStart: monday, calendar: calendar)

        #expect(report.isEmpty)
        #expect(report.totalSeconds == 0)
        #expect(report.days.count == 7)
        #expect(report.dayGroups.isEmpty)
    }

    @Test("Сумма и количество записей")
    func totals() {
        let report = WeekReport(
            entries: [
                worklog(id: 1, issue: "A-1", day: 7, seconds: 3600),
                worklog(id: 2, issue: "A-2", day: 8, seconds: 1800)
            ],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.totalSeconds == 5400)
        #expect(report.entryCount == 2)
    }

    @Test("Всегда семь дней, даже пустых")
    func alwaysSevenDays() {
        let report = WeekReport(
            entries: [worklog(id: 1, issue: "A-1", day: 7, seconds: 3600)],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.days.count == 7)
        #expect(report.days[0].seconds == 3600)
        #expect(report.days[1].seconds == 0)
    }

    /// В разбивке по дням пустые дни не показываются.
    @Test("Группы по дням пропускают пустые дни")
    func dayGroupsSkipEmptyDays() {
        let report = WeekReport(
            entries: [
                worklog(id: 1, issue: "A-1", day: 7, seconds: 3600),
                worklog(id: 2, issue: "A-2", day: 9, seconds: 3600)
            ],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.dayGroups.count == 2)
    }

    @Test("Записи одной задачи складываются")
    func entriesOfSameIssueAreSummed() {
        let report = WeekReport(
            entries: [
                worklog(id: 1, issue: "A-1", day: 7, hour: 10, seconds: 3600),
                worklog(id: 2, issue: "A-1", day: 8, hour: 10, seconds: 1800)
            ],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.issues.count == 1)
        #expect(report.issues[0].seconds == 5400)
        #expect(report.issues[0].entries.count == 2)
    }

    @Test("Задачи отсортированы по убыванию времени")
    func issuesAreSortedByTimeDescending() {
        let report = WeekReport(
            entries: [
                worklog(id: 1, issue: "SMALL-1", day: 7, seconds: 600),
                worklog(id: 2, issue: "BIG-1", day: 8, seconds: 7200)
            ],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.issues.map(\.key) == ["BIG-1", "SMALL-1"])
    }

    @Test("Уникальные задачи в дне считаются один раз")
    func dayGroupCountsUniqueIssues() {
        let report = WeekReport(
            entries: [
                worklog(id: 1, issue: "A-1", day: 7, hour: 10, seconds: 600),
                worklog(id: 2, issue: "A-1", day: 7, hour: 14, seconds: 600),
                worklog(id: 3, issue: "A-2", day: 7, hour: 16, seconds: 600)
            ],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.dayGroups.count == 1)
        #expect(report.dayGroups[0].issueCount == 2)
        #expect(report.dayGroups[0].entries.count == 3)
    }

    @Test("Записи внутри дня отсортированы по времени")
    func entriesInsideDayAreSortedByTime() {
        let report = WeekReport(
            entries: [
                worklog(id: 1, issue: "A-1", day: 7, hour: 17, seconds: 600),
                worklog(id: 2, issue: "A-2", day: 7, hour: 9, seconds: 600)
            ],
            weekStart: monday,
            calendar: calendar
        )

        #expect(report.dayGroups[0].entries.map(\.id) == [2, 1])
    }
}

@Suite("Границы недели")
struct WeekMathTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Неделя начинается с понедельника")
    func weekStartsOnMonday() {
        // 10 сентября 2026 — четверг.
        let start = WeekMath.weekStart(offset: 0, now: date(year: 2026, month: 9, day: 10), calendar: calendar)

        #expect(calendar.component(.day, from: start) == 7)
        #expect(calendar.component(.weekday, from: start) == 2)
    }

    @Test("Отрицательный сдвиг уводит в прошлые недели")
    func negativeOffsetGoesBack() {
        let start = WeekMath.weekStart(offset: -1, now: date(year: 2026, month: 9, day: 10), calendar: calendar)

        #expect(calendar.component(.day, from: start) == 31)
        #expect(calendar.component(.month, from: start) == 8)
    }

    @Test("Конец недели — ровно через семь дней")
    func weekEndIsSevenDaysLater() {
        let start = WeekMath.weekStart(offset: 0, now: date(year: 2026, month: 9, day: 10), calendar: calendar)
        let end = WeekMath.weekEnd(from: start, calendar: calendar)

        #expect(calendar.dateComponents([.day], from: start, to: end).day == 7)
    }

    @Test("Воскресенье относится к начавшейся в понедельник неделе")
    func sundayBelongsToPreviousMonday() {
        let start = WeekMath.weekStart(offset: 0, now: date(year: 2026, month: 9, day: 13), calendar: calendar)

        #expect(calendar.component(.day, from: start) == 7)
    }
}
