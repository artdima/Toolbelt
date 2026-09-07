//
//  WeeklyReportViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

enum BreakdownMode: String, CaseIterable, Identifiable {
    case issues
    case days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .issues: return "By issue"
        case .days: return "By day"
        }
    }
}

@Observable
@MainActor
final class WeeklyReportViewModel {
    private let tracker: TrackerService
    private let credentialsStore: TrackerCredentialsStore

    private(set) var report = WeekReport.empty
    private(set) var errorMessage: String?

    /// A counter rather than a Bool: a manual refresh and a week change can overlap,
    /// and whichever finishes first must not switch off the other one's spinner.
    private var inFlightCount = 0
    private var loadTask: Task<Void, Never>?

    private(set) var weekOffset = 0
    var breakdownMode: BreakdownMode = .issues
    private(set) var expandedIssues: Set<String> = []
    private(set) var expandedDays: Set<Date> = []

    convenience init() {
        self.init(tracker: TrackerClient(), credentialsStore: .shared)
    }

    init(tracker: TrackerService, credentialsStore: TrackerCredentialsStore) {
        self.tracker = tracker
        self.credentialsStore = credentialsStore
    }

    // MARK: State

    var isLoading: Bool { inFlightCount > 0 }
    var credentials: TrackerCredentials { credentialsStore.credentials }
    var isConfigured: Bool { credentials.isConfigured }
    var canShowNextWeek: Bool { weekOffset < 0 }

    var weekStart: Date { WeekMath.weekStart(offset: weekOffset) }

    var weekRangeTitle: String {
        let calendar = AppFormatters.calendar
        let start = weekStart
        let last = calendar.date(byAdding: .day, value: WeekMath.daysInWeek - 1, to: start) ?? start
        let formatter = AppFormatters.monthAndDay
        return "\(formatter.string(from: start)) — \(formatter.string(from: last))"
    }

    var relativeWeekTitle: String {
        switch weekOffset {
        case 0: return "This week"
        case -1: return "Last week"
        case ..<0: return "\(Plural.counted(abs(weekOffset), "week", "weeks")) ago"
        default: return "In \(Plural.counted(weekOffset, "week", "weeks"))"
        }
    }

    // MARK: Actions

    func changeWeek(by delta: Int) {
        weekOffset += delta
        // The expanded rows belong to last week's entries — collapse them.
        expandedIssues.removeAll()
        expandedDays.removeAll()
    }

    func toggleIssue(_ key: String) {
        toggle(key, in: &expandedIssues)
    }

    func toggleDay(_ date: Date) {
        toggle(date, in: &expandedDays)
    }

    var isBreakdownEmpty: Bool {
        breakdownMode == .issues ? report.issues.isEmpty : report.dayGroups.isEmpty
    }

    var isBreakdownCollapsed: Bool {
        breakdownMode == .issues ? expandedIssues.isEmpty : expandedDays.isEmpty
    }

    func toggleExpandAll() {
        switch breakdownMode {
        case .issues:
            expandedIssues = expandedIssues.isEmpty ? Set(report.issues.map(\.key)) : []
        case .days:
            expandedDays = expandedDays.isEmpty ? Set(report.dayGroups.map(\.date)) : []
        }
    }

    // MARK: Loading

    func reload() async {
        loadTask?.cancel()
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        guard isConfigured else {
            report = .empty
            return
        }

        let requestedOffset = weekOffset
        let start = weekStart
        let end = WeekMath.weekEnd(from: start)

        inFlightCount += 1
        errorMessage = nil
        defer { inFlightCount -= 1 }

        do {
            let entries = try await tracker.worklog(from: start, to: end)
            try Task.checkCancellation()
            // The user may have switched weeks while the request was in flight.
            guard requestedOffset == weekOffset else { return }
            report = WeekReport(entries: entries, weekStart: start)
        } catch is CancellationError {
            // Superseded by a newer request — leave the state alone.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            // Keep the data on screen: a banner over the previous report is more
            // useful than an empty screen with an error.
            errorMessage = error.localizedDescription
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
