//
//  WeeklyReportView.swift
//  Toolbelt
//
//  Отчёт по трудозатратам за неделю из Яндекс Трекера.
//

import SwiftUI

struct WeeklyReportView: View {
    @State private var model = WeeklyReportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage = model.errorMessage {
                ErrorBanner(text: errorMessage)
            }

            content
        }
        .frame(minWidth: 460, minHeight: 480)
        .onChange(of: model.credentials) { _, _ in
            Task { await model.reload() }
        }
        .task(id: model.weekOffset) {
            await model.reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConfigured {
            SetupPrompt(
                text: "Укажите OAuth-токен и идентификатор организации,\nчтобы получить отчёт из Яндекс Трекера",
                actionTitle: "Открыть настройки"
            ) {
                AppWindows.settings(tab: .tracker)
            }
        } else if model.isLoading && model.report.isEmpty {
            LoadingState(text: "Загружаем записи из Трекера…")
        } else if model.report.isEmpty {
            EmptyState(systemImage: "clock.badge.questionmark", text: "За эту неделю записей нет")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    totalCard
                    daysSection
                    breakdownSection
                }
                .padding(16)
            }
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.changeWeek(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Предыдущая неделя")

            Button { model.changeWeek(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!model.canShowNextWeek)
            .help("Следующая неделя")

            VStack(alignment: .leading, spacing: 1) {
                Text(model.weekRangeTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(model.relativeWeekTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            Spacer()

            if model.isLoading {
                ProgressView().controlSize(.small)
            }

            RefreshButton(isDisabled: model.isLoading) {
                Task { await model.reload() }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Секции

    private var totalCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Всего за неделю")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.short(model.report.totalSeconds))
                    .font(.system(size: 24, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Plural.counted(model.report.entryCount, "запись", "записи", "записей"))
                Text(Plural.counted(model.report.issues.count, "задача", "задачи", "задач"))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var daysSection: some View {
        let days = model.report.days
        let maxSeconds = max(days.map(\.seconds).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("По дням")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(days) { day in
                    HStack(spacing: 10) {
                        Text(AppFormatters.weekdayAndDay.string(from: day.date).capitalizedFirst)
                            .font(.system(size: 12, weight: isToday(day.date) ? .semibold : .regular))
                            .frame(width: 92, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 8)
                            Capsule()
                                .fill(day.seconds > 0 ? Color.accentColor : Color.clear)
                                .frame(width: barWidth(day.seconds, relativeTo: maxSeconds), height: 8)
                        }
                        .frame(maxWidth: .infinity)

                        Text(day.seconds > 0 ? DurationFormatter.short(day.seconds) : "—")
                            .font(.system(size: 12))
                            .foregroundStyle(day.seconds > 0 ? Color.primary : Color.secondary)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $model.breakdownMode) {
                    ForEach(BreakdownMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()

                Spacer()

                if !model.isBreakdownEmpty {
                    Button(model.isBreakdownCollapsed ? "Раскрыть все" : "Свернуть все") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            model.toggleExpandAll()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                switch model.breakdownMode {
                case .issues:
                    separated(model.report.issues) { issueRow($0) }
                case .days:
                    separated(model.report.dayGroups) { dayRow($0) }
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Разделители между строками, но не перед первой.
    private func separated<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { Divider() }
            row(item)
        }
    }

    private func issueRow(_ issue: WeekReport.IssueTotal) -> some View {
        ExpandableRow(
            isExpanded: model.expandedIssues.contains(issue.key),
            toggle: { model.toggleIssue(issue.key) }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text(issue.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        } trailing: {
            RowTotals(
                value: DurationFormatter.short(issue.seconds),
                caption: Plural.counted(issue.entries.count, "запись", "записи", "записей")
            )
        } details: {
            WorklogEntryList(entries: issue.entries, showsDate: true)
        }
    }

    private func dayRow(_ group: WeekReport.DayGroup) -> some View {
        ExpandableRow(
            isExpanded: model.expandedDays.contains(group.date),
            toggle: { model.toggleDay(group.date) }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppFormatters.weekdayAndDay.string(from: group.date).capitalizedFirst)
                    .font(.system(size: 12, weight: isToday(group.date) ? .semibold : .regular))
                Text(Plural.counted(group.issueCount, "задача", "задачи", "задач"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        } trailing: {
            RowTotals(
                value: DurationFormatter.short(group.seconds),
                caption: Plural.counted(group.entries.count, "запись", "записи", "записей")
            )
        } details: {
            WorklogEntryList(entries: group.entries, showsDate: false)
        }
    }

    // MARK: Вспомогательное

    private func isToday(_ date: Date) -> Bool {
        AppFormatters.calendar.isDateInToday(date)
    }

    private func barWidth(_ seconds: TimeInterval, relativeTo maxSeconds: TimeInterval) -> CGFloat {
        guard seconds > 0 else { return 0 }
        return max(6, CGFloat(seconds / maxSeconds) * 200)
    }
}

#Preview {
    WeeklyReportView()
}
