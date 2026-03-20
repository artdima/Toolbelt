//
//  IssuesBoardView.swift
//  Toolbelt
//
//  Канбан-доска: задачи, где я исполнитель, разложенные по колонкам-статусам.
//

import SwiftUI

// MARK: - Окно доски

enum IssuesBoardWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: IssuesBoardView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Мои задачи"
        newWindow.setContentSize(NSSize(width: 980, height: 640))
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

// MARK: - Колонка

private struct StatusColumn: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let issues: [Issue]
}

// MARK: - Доска

struct IssuesBoardView: View {
    @State private var issues: [Issue] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var includeResolved = false
    @State private var search = ""
    @State private var isSettingsPresented = false

    /// Порядок колонок: сначала известные статусы в логичной последовательности,
    /// остальные — следом по алфавиту.
    private let statusOrder = [
        "open", "needInfo", "new", "backlog",
        "inProgress", "inDevelopment", "development",
        "readyForReview", "review", "codeReview",
        "readyForTest", "testing", "acceptance",
        "readyForRelease", "released", "resolved", "closed"
    ]

    private var filtered: [Issue] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return issues }
        return issues.filter {
            $0.key.lowercased().contains(query) || $0.summary.lowercased().contains(query)
        }
    }

    private var columns: [StatusColumn] {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [Issue]] = [:]

        for issue in filtered {
            if grouped[issue.statusKey] == nil {
                order.append(issue.statusKey)
                names[issue.statusKey] = issue.statusName
            }
            grouped[issue.statusKey, default: []].append(issue)
        }

        return order
            .map { StatusColumn(key: $0, name: names[$0] ?? $0, issues: grouped[$0] ?? []) }
            .sorted { left, right in
                let leftRank = statusOrder.firstIndex(of: left.key) ?? Int.max
                let rightRank = statusOrder.firstIndex(of: right.key) ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    // MARK: Тело

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage {
                Text("⚠ \(errorMessage)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
            }

            if !TrackerCredentials.isConfigured {
                VStack(spacing: 12) {
                    Image(systemName: "key")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("Укажите OAuth-токен и идентификатор организации")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Открыть настройки") { isSettingsPresented = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading && issues.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем задачи…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if columns.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(issues.isEmpty ? "Задач не найдено" : "Ничего не найдено по запросу")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                board
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: $isSettingsPresented) {
            TrackerSettingsView {
                Task { await load() }
            }
        }
        .task(id: includeResolved) {
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Мои задачи")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(filtered.count) \(pluralize(filtered.count, "задача", "задачи", "задач")) в \(columns.count) \(pluralize(columns.count, "статусе", "статусах", "статусах"))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Поиск по ключу или названию", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Toggle("Решённые", isOn: $includeResolved)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

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

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(column.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text("\(column.issues.count)")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(column.issues) { issue in
                                    IssueCard(issue: issue)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .frame(width: 264)
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14)
        }
    }

    private func pluralize(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 { return few }
        return many
    }

    private func load() async {
        guard TrackerCredentials.isConfigured else {
            issues = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            issues = try await TrackerAPI.fetchMyIssues(includeResolved: includeResolved)
        } catch {
            issues = []
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Карточка задачи

private struct IssueCard: View {
    let issue: Issue

    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = issue.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 6, height: 6)
                    Text(issue.key)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if isHovered {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(issue.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if !issue.queueName.isEmpty {
                        Text(issue.queueName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let deadline = issue.deadline {
                        Label(dayFormatter.string(from: deadline), systemImage: "flag")
                            .font(.system(size: 9))
                            .foregroundStyle(issue.isOverdue ? Color.red : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isHovered ? Color.primary.opacity(0.09) : Color.primary.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(issue.key) — открыть в браузере")
        .contextMenu {
            Button("Открыть в браузере") {
                if let url = issue.url { NSWorkspace.shared.open(url) }
            }
            Button("Скопировать ключ") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(issue.key, forType: .string)
            }
        }
    }

    private var priorityColor: Color {
        switch issue.priorityKey {
        case "blocker", "critical": return .red
        case "major": return .orange
        case "minor", "trivial": return .gray
        default: return .blue
        }
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }
}

#Preview {
    IssuesBoardView()
}
