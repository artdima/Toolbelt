//
//  WeekReport.swift
//  Toolbelt
//
//  Aggregating a week of worklog entries. Pure logic, no SwiftUI: computed once
//  after a load rather than on every redraw.
//

import Foundation

enum WeekMath {
    static let daysInWeek = 7

    /// The start of the week `offset` weeks away from the current one.
    static func weekStart(
        offset: Int,
        now: Date = Date(),
        calendar: Calendar = AppFormatters.calendar
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let current = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .weekOfYear, value: offset, to: current) ?? current
    }

    static func weekEnd(from start: Date, calendar: Calendar = AppFormatters.calendar) -> Date {
        calendar.date(byAdding: .day, value: daysInWeek, to: start) ?? start
    }
}

struct WeekReport: Equatable {
    struct Day: Identifiable, Equatable {
        let id: Int
        let date: Date
        let seconds: TimeInterval
    }

    struct IssueTotal: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let title: String
        let seconds: TimeInterval
        let entries: [Worklog]
    }

    struct DayGroup: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let seconds: TimeInterval
        let issueCount: Int
        let entries: [Worklog]
    }

    let totalSeconds: TimeInterval
    let entryCount: Int
    let days: [Day]
    let issues: [IssueTotal]
    let dayGroups: [DayGroup]

    var isEmpty: Bool { entryCount == 0 }

    static let empty = WeekReport(entries: [], weekStart: Date())

    init(entries: [Worklog], weekStart: Date, calendar: Calendar = AppFormatters.calendar) {
        totalSeconds = entries.reduce(0) { $0 + $1.seconds }
        entryCount = entries.count

        var days: [Day] = []
        var dayGroups: [DayGroup] = []

        for offset in 0..<WeekMath.daysInWeek {
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let items = entries
                .filter { $0.start >= date && $0.start < next }
                .sorted { $0.start < $1.start }
            let seconds = items.reduce(0) { $0 + $1.seconds }

            days.append(Day(id: offset, date: date, seconds: seconds))

            if !items.isEmpty {
                dayGroups.append(
                    DayGroup(
                        date: date,
                        seconds: seconds,
                        issueCount: Set(items.map(\.issueKey)).count,
                        entries: items
                    )
                )
            }
        }

        self.days = days
        self.dayGroups = dayGroups
        issues = Self.groupByIssue(entries)
    }

    /// Issues are ordered by time spent, descending.
    private static func groupByIssue(_ entries: [Worklog]) -> [IssueTotal] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var totals: [String: TimeInterval] = [:]
        var grouped: [String: [Worklog]] = [:]

        for entry in entries {
            if totals[entry.issueKey] == nil {
                order.append(entry.issueKey)
                titles[entry.issueKey] = entry.issueTitle
            }
            totals[entry.issueKey, default: 0] += entry.seconds
            grouped[entry.issueKey, default: []].append(entry)
        }

        return order
            .map { key in
                IssueTotal(
                    key: key,
                    title: titles[key] ?? key,
                    seconds: totals[key] ?? 0,
                    entries: (grouped[key] ?? []).sorted { $0.start < $1.start }
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }
}
