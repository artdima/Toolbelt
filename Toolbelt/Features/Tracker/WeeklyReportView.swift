//
//  WeeklyReportView.swift
//  Toolbelt
//
//  A week of logged time from Yandex Tracker.
//

import SwiftUI

struct WeeklyReportView: View {
    @State private var model = WeeklyReportViewModel()

    var body: some View {
        content
            .frame(minWidth: 440, minHeight: 460)
            .navigationTitle("Weekly Report")
            .toolbar { weekToolbar }
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
                text: "Set an OAuth token and an organization ID\nto pull the report from Yandex Tracker",
                actionTitle: "Open Settings"
            ) {
                AppWindows.settings(tab: .tracker)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                summary
                    .padding(.bottom, 12)

                if let failure = model.failure, !model.report.isEmpty {
                    ErrorBanner(text: failure.reason, details: failure.details)
                        .padding(.bottom, 10)
                }

                report
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var report: some View {
        if let failure = model.failure, model.report.isEmpty {
            failureState(failure)
        } else if model.isLoading && model.report.isEmpty {
            LoadingState(text: "Loading entries from Tracker…")
        } else if model.report.isEmpty {
            EmptyState(systemImage: "clock.badge.questionmark", text: "No entries this week")
        } else {
            chartCard
                .padding(.bottom, 12)
            breakdownControls
                .padding(.bottom, 6)
            breakdownList
        }
    }

    private func failureState(_ failure: TrackerFailure) -> some View {
        ErrorState(
            title: "Unable to load report",
            message: failure.message,
            details: failure.details,
            retry: { Task { await model.reload() } }
        ) {
            if failure.needsSettings {
                Button("Open Settings") { AppWindows.settings(tab: .tracker) }
            } else if model.weekOffset != 0 {
                Button("This week") { model.changeWeek(by: -model.weekOffset) }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var weekToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.changeWeek(by: -1) } label: {
                Label("Previous Week", systemImage: "chevron.left")
            }
            .disabled(!model.isConfigured)
            .help("Previous week")

            Button { model.changeWeek(by: 1) } label: {
                Label("Next Week", systemImage: "chevron.right")
            }
            .disabled(!model.isConfigured || !model.canShowNextWeek)
            .help("Next week")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button { Task { await model.reload() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.isConfigured)
                .keyboardShortcut("r")
                .help("Refresh")
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.weekRangeTitle)
                    .font(.system(size: 16, weight: .bold))
                Text(model.relativeWeekTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !model.report.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DurationFormatter.short(model.report.totalSeconds))
                        .font(.system(size: 20, weight: .semibold))
                    Text(verbatim: "\(entriesCount) · \(issuesCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }

    private var entriesCount: String {
        Plural.counted(model.report.entryCount, "entry", "entries")
    }

    private var issuesCount: String {
        Plural.counted(model.report.issues.count, "issue", "issues")
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By day")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            WeekChart(days: model.report.days)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .card()
    }

    // MARK: Breakdown

    private var breakdownControls: some View {
        HStack(spacing: 8) {
            PillPicker(selection: $model.breakdownMode, options: BreakdownMode.allCases) { $0.title }

            Spacer()

            if !model.isBreakdownEmpty {
                Button(model.isBreakdownCollapsed ? "Expand all" : "Collapse all") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.toggleExpandAll()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.trailing, 10)
            }
        }
    }

    private var breakdownList: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch model.breakdownMode {
                case .issues:
                    separated(model.report.issues) { issueRow($0) }
                case .days:
                    separated(model.report.dayGroups) { dayRow($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    /// Dividers between rows, but not above the first one.
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
        BreakdownRow(
            isExpanded: model.expandedIssues.contains(issue.key),
            toggle: { model.toggleIssue(issue.key) },
            seconds: issue.seconds,
            share: model.report.share(of: issue.seconds),
            count: Plural.counted(issue.entries.count, "entry", "entries")
        ) {
            Text(issue.key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            Text(issue.title)
                .font(.system(size: 13))
                .lineLimit(2)
                .textSelection(.enabled)
        } details: {
            WorklogEntryList(entries: issue.entries, showsDate: true)
        }
    }

    private func dayRow(_ group: WeekReport.DayGroup) -> some View {
        BreakdownRow(
            isExpanded: model.expandedDays.contains(group.date),
            toggle: { model.toggleDay(group.date) },
            seconds: group.seconds,
            share: model.report.share(of: group.seconds),
            count: Plural.counted(group.entries.count, "entry", "entries")
        ) {
            Text(AppFormatters.weekdayAndDay.string(from: group.date))
                .font(.system(size: 13, weight: isToday(group.date) ? .semibold : .regular))
            Text(Plural.counted(group.issueCount, "issue", "issues"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } details: {
            WorklogEntryList(entries: group.entries, showsDate: false)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        AppFormatters.calendar.isDateInToday(date)
    }
}

#Preview {
    WeeklyReportView()
}
