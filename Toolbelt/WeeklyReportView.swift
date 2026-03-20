//
//  WeeklyReportView.swift
//  Toolbelt
//
//  Окно с отчётом по трудозатратам за неделю из Яндекс Трекера.
//

import SwiftUI

// MARK: - Окно отчёта

enum WeeklyReportWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: WeeklyReportView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Отчёт за неделю"
        newWindow.setContentSize(NSSize(width: 520, height: 660))
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { _ in
            window = nil
            DockPresence.release()
        }

        newWindow.makeKeyAndOrderFront(nil)
        DockPresence.activate()
    }
}

// MARK: - Агрегаты

private struct DayBucket: Identifiable {
    let id: Int
    let date: Date
    let seconds: TimeInterval
}

private struct IssueBucket: Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let seconds: TimeInterval
    /// Исходные записи worklog по задаче — раскрываются по «+».
    let entries: [Worklog]
}

private struct DayGroup: Identifiable {
    var id: Date { date }
    let date: Date
    let seconds: TimeInterval
    let issueCount: Int
    let entries: [Worklog]
}

private enum BreakdownMode: String, CaseIterable, Identifiable {
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

// MARK: - Вью отчёта

struct WeeklyReportView: View {
    @State private var weekOffset = 0
    @State private var entries: [Worklog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSettingsPresented = false
    /// Ключи задач, у которых раскрыта детализация по записям.
    @State private var expandedIssues: Set<String> = []
    @State private var expandedDays: Set<Date> = []
    @State private var breakdownMode: BreakdownMode = .issues

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // понедельник
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "ru_RU")
        return calendar
    }

    private var weekStart: Date {
        let today = calendar.startOfDay(for: Date())
        let current = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: current) ?? current
    }

    private var weekEnd: Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    private var totalSeconds: TimeInterval {
        entries.reduce(0) { $0 + $1.seconds }
    }

    private var days: [DayBucket] {
        (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let seconds = entries
                .filter { $0.start >= date && $0.start < next }
                .reduce(0) { $0 + $1.seconds }
            return DayBucket(id: offset, date: date, seconds: seconds)
        }
    }

    private var issues: [IssueBucket] {
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
                IssueBucket(
                    key: key,
                    title: titles[key] ?? key,
                    seconds: totals[key] ?? 0,
                    entries: (grouped[key] ?? []).sorted { $0.start < $1.start }
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private var dayGroups: [DayGroup] {
        days.compactMap { day in
            let next = calendar.date(byAdding: .day, value: 1, to: day.date) ?? day.date
            let items = entries
                .filter { $0.start >= day.date && $0.start < next }
                .sorted { $0.start < $1.start }
            guard !items.isEmpty else { return nil }
            return DayGroup(
                date: day.date,
                seconds: items.reduce(0) { $0 + $1.seconds },
                issueCount: Set(items.map(\.issueKey)).count,
                entries: items
            )
        }
    }

    // MARK: Тело

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage {
                banner(errorMessage)
            }

            if !TrackerCredentials.isConfigured {
                setupPrompt
            } else if isLoading && entries.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем записи из Трекера…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("За эту неделю записей нет")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(minWidth: 460, minHeight: 480)
        .sheet(isPresented: $isSettingsPresented) {
            TrackerSettingsView {
                Task { await load() }
            }
        }
        .task(id: weekOffset) {
            // При смене недели детализация схлопывается; ручное обновление её сохраняет.
            expandedIssues.removeAll()
            expandedDays.removeAll()
            await load()
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Предыдущая неделя")

            Button {
                weekOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(weekOffset >= 0)
            .help("Следующая неделя")

            VStack(alignment: .leading, spacing: 1) {
                Text(weekRangeTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(weekOffset == 0 ? "Текущая неделя" : relativeWeekTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("Обновить")

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Настройки доступа к Трекеру")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func banner(_ text: String) -> some View {
        Text("⚠ \(text)")
            .font(.system(size: 11))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
    }

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Укажите OAuth-токен и идентификатор организации,\nчтобы получить отчёт из Яндекс Трекера")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Открыть настройки") { isSettingsPresented = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Секции

    private var totalCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Всего за неделю")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(TrackerAPI.formatDuration(totalSeconds))
                    .font(.system(size: 24, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entries.count) \(pluralize(entries.count, "запись", "записи", "записей"))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(issues.count) \(pluralize(issues.count, "задача", "задачи", "задач"))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("По дням")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            let maxSeconds = max(days.map(\.seconds).max() ?? 0, 1)

            VStack(spacing: 6) {
                ForEach(days) { day in
                    HStack(spacing: 10) {
                        Text(dayTitle(day.date))
                            .font(.system(size: 12, weight: isToday(day.date) ? .semibold : .regular))
                            .frame(width: 92, alignment: .leading)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 8)
                            Capsule()
                                .fill(day.seconds > 0 ? Color.accentColor : Color.clear)
                                .frame(width: barWidth(day.seconds, max: maxSeconds), height: 8)
                        }
                        .frame(maxWidth: .infinity)

                        Text(day.seconds > 0 ? TrackerAPI.formatDuration(day.seconds) : "—")
                            .font(.system(size: 12))
                            .foregroundStyle(day.seconds > 0 ? .primary : .tertiary)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $breakdownMode) {
                    ForEach(BreakdownMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()

                Spacer()

                if !isBreakdownEmpty {
                    Button(expandAllTitle) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            toggleExpandAll()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                switch breakdownMode {
                case .issues:
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                        if index > 0 { Divider() }
                        issueRow(issue)
                    }
                case .days:
                    ForEach(Array(dayGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider() }
                        dayRow(group)
                    }
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var isBreakdownEmpty: Bool {
        breakdownMode == .issues ? issues.isEmpty : dayGroups.isEmpty
    }

    private var expandAllTitle: String {
        let isCollapsed = breakdownMode == .issues ? expandedIssues.isEmpty : expandedDays.isEmpty
        return isCollapsed ? "Раскрыть все" : "Свернуть все"
    }

    private func toggleExpandAll() {
        switch breakdownMode {
        case .issues:
            expandedIssues = expandedIssues.isEmpty ? Set(issues.map(\.key)) : []
        case .days:
            expandedDays = expandedDays.isEmpty ? Set(dayGroups.map(\.date)) : []
        }
    }

    private var detailsShowHint: String { "Показать детализацию" }
    private var detailsHideHint: String { "Свернуть детализацию" }

    @ViewBuilder
    private func issueRow(_ issue: IssueBucket) -> some View {
        let isExpanded = expandedIssues.contains(issue.key)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isExpanded {
                            expandedIssues.remove(issue.key)
                        } else {
                            expandedIssues.insert(issue.key)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? detailsHideHint : detailsShowHint)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.key)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Text(issue.title)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TrackerAPI.formatDuration(issue.seconds))
                        .font(.system(size: 12, weight: .medium))
                    Text("\(issue.entries.count) \(pluralize(issue.entries.count, "запись", "записи", "записей"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

            if isExpanded {
                issueDetails(issue)
            }
        }
    }

    private func issueDetails(_ issue: IssueBucket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(issue.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().padding(.leading, 12)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(entryDateTitle(entry.start))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 108, alignment: .leading)

                    if let comment = entry.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Без комментария")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(TrackerAPI.formatDuration(entry.seconds))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
        }
        .padding(.leading, 24)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private func dayRow(_ group: DayGroup) -> some View {
        let isExpanded = expandedDays.contains(group.date)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isExpanded {
                            expandedDays.remove(group.date)
                        } else {
                            expandedDays.insert(group.date)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? detailsHideHint : detailsShowHint)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dayTitle(group.date))
                        .font(.system(size: 12, weight: isToday(group.date) ? .semibold : .regular))
                    Text("\(group.issueCount) \(pluralize(group.issueCount, "задача", "задачи", "задач"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TrackerAPI.formatDuration(group.seconds))
                        .font(.system(size: 12, weight: .medium))
                    Text("\(group.entries.count) \(pluralize(group.entries.count, "запись", "записи", "записей"))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

            if isExpanded {
                dayDetails(group)
            }
        }
    }

    private func dayDetails(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().padding(.leading, 12)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(timeTitle(entry.start))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.issueKey)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)

                        if let comment = entry.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Без комментария")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(TrackerAPI.formatDuration(entry.seconds))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
        }
        .padding(.leading, 24)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: Вспомогательное

    private func barWidth(_ seconds: TimeInterval, max maxSeconds: TimeInterval) -> CGFloat {
        guard seconds > 0 else { return 0 }
        let ratio = seconds / maxSeconds
        return Swift.max(6, CGFloat(ratio) * 200)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE, d MMM"
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// «Пн, 18 авг · 10:30» — заголовок отдельной записи в детализации.
    private func entryDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE, d MMM"
        let day = formatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "ru_RU")
        timeFormatter.dateFormat = "HH:mm"

        return "\(day.prefix(1).uppercased())\(day.dropFirst()) · \(timeFormatter.string(from: date))"
    }

    private func timeTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var weekRangeTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        let last = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart)) — \(formatter.string(from: last))"
    }

    private var relativeWeekTitle: String {
        let weeks = abs(weekOffset)
        if weekOffset == -1 { return "Прошлая неделя" }
        if weekOffset < 0 { return "\(weeks) \(pluralize(weeks, "неделя", "недели", "недель")) назад" }
        return "Через \(weeks) \(pluralize(weeks, "неделю", "недели", "недель"))"
    }

    private func pluralize(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 { return few }
        return many
    }

    // MARK: Загрузка

    private func load() async {
        guard TrackerCredentials.isConfigured else {
            entries = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            entries = try await TrackerAPI.fetchWorklog(from: weekStart, to: weekEnd)
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Настройки доступа

struct TrackerSettingsView: View {
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token: String = TrackerCredentials.token
    @State private var orgId: String = TrackerCredentials.orgId
    @State private var orgKind: TrackerOrgKind = TrackerCredentials.orgKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Доступ к Яндекс Трекеру")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text("OAuth-токен")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                SecureField("y0_Ag…", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Хранится в Keychain. Получить: oauth.yandex.ru")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Идентификатор организации")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("123456", text: $orgId)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Тип организации")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $orgKind) {
                    ForEach(TrackerOrgKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Заголовок запроса: \(orgKind.headerName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    TrackerCredentials.token = token
                    TrackerCredentials.orgId = orgId.trimmingCharacters(in: .whitespacesAndNewlines)
                    TrackerCredentials.orgKind = orgKind
                    dismiss()
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 380)
    }
}

#Preview {
    WeeklyReportView()
}
