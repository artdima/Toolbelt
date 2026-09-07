//
//  IssuesBoardView.swift
//  Toolbelt
//
//  A kanban of your issues: columns are Tracker statuses.
//

import SwiftUI

struct IssuesBoardView: View {
    @State private var model = IssuesBoardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage = model.errorMessage {
                ErrorBanner(text: errorMessage)
            }

            content
        }
        .frame(minWidth: 640, minHeight: 420)
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

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("My Issues")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search by key or summary", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Toggle("Resolved", isOn: $model.includeResolved)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

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

    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.board.columns) { column in
                    columnView(column)
                }
            }
            .padding(14)
        }
    }

    private func columnView(_ column: IssuesBoard.Column) -> some View {
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

// MARK: - Issue card

private struct IssueCard: View {
    let issue: Issue

    @State private var isHovered = false

    var body: some View {
        Button {
            open()
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
                        Label(AppFormatters.shortDay.string(from: deadline), systemImage: "flag")
                            .font(.system(size: 9))
                            .foregroundStyle(issue.isOverdue() ? Color.red : Color.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(isHovered ? 0.09 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
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

    private func open() {
        guard let url = issue.url else { return }
        NSWorkspace.shared.open(url)
    }

    private var priorityColor: Color {
        switch issue.priorityKey {
        case "blocker", "critical": return .red
        case "major": return .orange
        case "minor", "trivial": return .gray
        default: return .blue
        }
    }
}

#Preview {
    IssuesBoardView()
}
