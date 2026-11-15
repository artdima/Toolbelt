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
    let source: WorklogSource
    private let service: WorklogService
    private let editor: WorklogEditing?

    private(set) var report = WeekReport.empty
    private(set) var failure: TrackerFailure?
    private var entries: [Worklog] = []

    var editingEntry: Worklog?
    var entryPendingDeletion: Worklog?
    var deletionFailure: TrackerFailure?
    private(set) var deletingEntryIDs: Set<Int> = []

    /// A counter rather than a Bool: a manual refresh and a week change can overlap,
    /// and whichever finishes first must not switch off the other one's spinner.
    private var inFlightCount = 0
    private var loadTask: Task<Void, Never>?

    private(set) var weekOffset = 0
    var breakdownMode: BreakdownMode = .issues
    private(set) var expandedIssues: Set<String> = []
    private(set) var expandedDays: Set<Date> = []

    convenience init(source: WorklogSource) {
        self.init(source: source, service: source.makeService())
    }

    init(source: WorklogSource, service: WorklogService) {
        self.source = source
        self.service = service
        editor = service as? WorklogEditing
    }

    // MARK: State

    var isLoading: Bool { inFlightCount > 0 }
    var isConfigured: Bool { service.isConfigured }
    var canEditEntries: Bool { editor != nil }
    var settingsRevision: AnyHashable { service.settingsRevision }
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

    // MARK: Editing entries

    func saveComment(_ text: String, for entry: Worklog) async -> TrackerFailure? {
        guard let editor else { return nil }
        let comment = text.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let updated = try await editor.updateComment(of: entry, to: comment)
            applyChange(entries.map { $0.id == updated.id ? updated : $0 })
            return nil
        } catch {
            reloadIfEntryIsGone(error)
            return TrackerFailure.worklogChange(error)
        }
    }

    func delete(_ entry: Worklog) async {
        guard let editor, !deletingEntryIDs.contains(entry.id) else { return }
        deletingEntryIDs.insert(entry.id)
        defer { deletingEntryIDs.remove(entry.id) }

        do {
            try await editor.delete(entry)
            applyChange(entries.filter { $0.id != entry.id })
        } catch {
            reloadIfEntryIsGone(error)
            deletionFailure = TrackerFailure.worklogChange(error)
        }
    }

    private func reloadIfEntryIsGone(_ error: Error) {
        if (error as? TrackerError) == .notFound {
            Task { await reload() }
        }
    }

    private func applyChange(_ updated: [Worklog]) {
        show(updated, weekStart: report.weekStart)
        expandedIssues.formIntersection(report.issues.map(\.key))
        expandedDays.formIntersection(report.dayGroups.map(\.date))

        // A load already in flight may have read the entries before the change.
        if isLoading {
            Task { await reload() }
        }
    }

    private func show(_ entries: [Worklog], weekStart: Date) {
        self.entries = entries
        report = WeekReport(entries: entries, weekStart: weekStart)
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
            entries = []
            report = .empty
            return
        }

        let requestedOffset = weekOffset
        let start = weekStart
        let end = WeekMath.weekEnd(from: start)

        inFlightCount += 1
        failure = nil
        defer { inFlightCount -= 1 }

        do {
            let loaded = try await service.worklog(from: start, to: end)
            try Task.checkCancellation()
            // The user may have switched weeks while the request was in flight.
            guard requestedOffset == weekOffset else { return }
            show(loaded, weekStart: start)
        } catch is CancellationError {
            // Superseded by a newer request — leave the state alone.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard requestedOffset == weekOffset else { return }
            // This week's data stays on screen under a banner; another week's
            // would pass for this one, so it goes.
            if report.weekStart != start {
                entries = []
                report = .empty
            }
            failure = source.failure(for: error)
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
