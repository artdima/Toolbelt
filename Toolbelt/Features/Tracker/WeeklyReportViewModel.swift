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
        case .issues: return "По задачам"
        case .days: return "По дням"
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

    /// Счётчик, а не Bool: ручное обновление и смена недели могут пересекаться,
    /// и завершившийся первым запрос не должен гасить чужой индикатор.
    private var inFlightCount = 0
    private var loadTask: Task<Void, Never>?

    private(set) var weekOffset = 0
    var breakdownMode: BreakdownMode = .issues
    private(set) var expandedIssues: Set<String> = []
    private(set) var expandedDays: Set<Date> = []

    init(
        tracker: TrackerService = TrackerClient(),
        credentialsStore: TrackerCredentialsStore = .shared
    ) {
        self.tracker = tracker
        self.credentialsStore = credentialsStore
    }

    // MARK: Состояние

    var isLoading: Bool { inFlightCount > 0 }
    var credentials: TrackerCredentials { credentialsStore.credentials }
    var isConfigured: Bool { credentials.isConfigured }
    var canShowNextWeek: Bool { weekOffset < 0 }

    var weekStart: Date { WeekMath.weekStart(offset: weekOffset) }

    var weekRangeTitle: String {
        let calendar = AppFormatters.calendar
        let start = weekStart
        let last = calendar.date(byAdding: .day, value: WeekMath.daysInWeek - 1, to: start) ?? start
        let formatter = AppFormatters.dayAndMonth
        return "\(formatter.string(from: start)) — \(formatter.string(from: last))"
    }

    var relativeWeekTitle: String {
        switch weekOffset {
        case 0: return "Текущая неделя"
        case -1: return "Прошлая неделя"
        case ..<0: return "\(Plural.counted(abs(weekOffset), "неделя", "недели", "недель")) назад"
        default: return "Через \(Plural.counted(weekOffset, "неделю", "недели", "недель"))"
        }
    }

    // MARK: Действия

    func changeWeek(by delta: Int) {
        weekOffset += delta
        // Детализация относится к записям прошлой недели — раскрытие сбрасываем.
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

    // MARK: Загрузка

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
            // Пока запрос летел, пользователь мог переключить неделю.
            guard requestedOffset == weekOffset else { return }
            report = WeekReport(entries: entries, weekStart: start)
        } catch is CancellationError {
            // Запрос вытеснен более свежим — состояние не трогаем.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            // Данные оставляем на экране: баннер поверх старого отчёта
            // полезнее, чем пустой экран с ошибкой.
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
