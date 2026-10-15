//
//  IssuesBoardView.swift
//  Toolbelt
//
//  A kanban of your issues: columns are Tracker statuses.
//

import SwiftUI

struct IssuesBoardView: View {
    @State private var model = IssuesBoardViewModel()

    private let boardPadding: CGFloat = 17
    private let columnSpacing: CGFloat = 12
    private let minColumnWidth: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            if let failure = model.failure, model.hasLoadedIssues {
                ErrorBanner(text: failure.reason, details: failure.details)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, boardPadding)
                    .padding(.top, 9)
            }

            content
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("My Issues")
        .navigationSubtitle(model.isConfigured && model.hasLoadedIssues ? model.summary : "")
        .toolbar { boardToolbar }
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Search by key or summary")
        .onChange(of: model.credentials) { _, _ in
            Task { await model.reload() }
        }
        .task(id: model.includeResolved) {
            await model.reload()
        }
        .onChange(of: model.searchQuery) { _, _ in
            model.rebuildBoard()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.isConfigured {
            SetupPrompt(
                text: "Set an OAuth token and an organization ID",
                actionTitle: "Open Settings"
            ) {
                AppWindows.settings(tab: .tracker)
            }
        } else if let failure = model.failure, !model.hasLoadedIssues {
            ErrorState(
                title: "Unable to load issues",
                message: failure.message,
                details: failure.details,
                retry: { Task { await model.reload() } }
            ) {
                if failure.needsSettings {
                    Button("Open Settings") { AppWindows.settings(tab: .tracker) }
                }
            }
        } else if model.isLoading && !model.hasLoadedIssues {
            LoadingState(text: "Loading issues…")
        } else if model.board.isEmpty {
            EmptyState(
                systemImage: "tray",
                text: model.hasLoadedIssues ? "Nothing matches the search" : "No issues found"
            )
        } else {
            board
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var boardToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.includeResolved) {
                if model.includeResolved {
                    Label("Resolved", systemImage: "checkmark")
                } else {
                    Text("Resolved")
                }
            }
            .toggleStyle(.button)
            .labelStyle(.titleAndIcon)
            .disabled(!model.isConfigured)
            .help(model.includeResolved ? "Hide resolved issues" : "Show resolved issues")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.isConfigured)
                .keyboardShortcut("r")
                .help("Refresh")
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: Board

    /// Columns share the window width and scroll sideways once they would get narrower
    /// than `minColumnWidth`.
    private var board: some View {
        GeometryReader { geometry in
            let columns = model.board.columns
            let count = CGFloat(max(columns.count, 1))
            let available = geometry.size.width - 2 * boardPadding - columnSpacing * (count - 1)
            let width = max(minColumnWidth, available / count)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(columns) { column in
                        columnView(column)
                            .frame(width: width)
                    }
                }
                .padding(.horizontal, boardPadding)
                .padding(.top, 9)
                .padding(.bottom, boardPadding)
                .frame(height: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private func columnView(_ column: IssuesBoard.Column) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(column.stage.color)
                    .frame(width: 8, height: 8)
                Text(column.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: "\(column.issues.count)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(column.issues) { issue in
                        IssueCard(issue: issue)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private extension IssuesBoard.Stage {
    var color: Color {
        switch self {
        case .waiting: Color.gray
        case .active: Color.blue
        case .review: Color.purple
        case .testing: Color.orange
        case .done: Color.green
        }
    }
}

// MARK: - Issue card

private struct IssueCard: View {
    let issue: Issue

    @State private var isHovered = false

    var body: some View {
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(issue.key)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 8)
                    PriorityBars(level: issue.priorityLevel, isUrgent: issue.isUrgent)
                        .help(issue.priorityName.isEmpty ? issue.priorityKey : issue.priorityName)
                }

                Text(issue.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                if !issue.queueName.isEmpty || issue.deadline != nil {
                    footer
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .card()
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.16 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(issue.key) — open in browser")
        .contextMenu {
            Button("Open in Browser", action: open)
            Button("Copy Key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(issue.key, forType: .string)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(issue.queueName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let deadline = issue.deadline {
                let tint = issue.isOverdue() ? Color.red : Color.secondary
                Label(AppFormatters.shortDay.string(from: deadline), systemImage: "flag")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.1), in: Capsule())
                    .help(issue.isOverdue() ? "Overdue" : "Deadline")
            }
        }
    }

    private func open() {
        guard let url = issue.url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Three bars like a signal meter; urgent priorities are drawn in red.
private struct PriorityBars: View {
    let level: Int
    let isUrgent: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(1...3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(bar <= level ? activeColor : Color.primary.opacity(0.15))
                    .frame(width: 2.5, height: CGFloat(2 + bar * 2))
            }
        }
        .accessibilityHidden(true)
    }

    private var activeColor: Color {
        isUrgent ? .red : Color.primary.opacity(0.6)
    }
}

#Preview {
    IssuesBoardView()
}
