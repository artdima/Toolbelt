//
//  WeeklyReportRows.swift
//  Toolbelt
//
//  Rows of the weekly report breakdown and their worklog details.
//

import SwiftUI

struct BreakdownRow<Title: View, Details: View>: View {
    private let isExpanded: Bool
    private let toggle: () -> Void
    private let seconds: TimeInterval
    private let share: Double
    private let count: String
    private let title: Title
    private let details: Details

    init(
        isExpanded: Bool,
        toggle: @escaping () -> Void,
        seconds: TimeInterval,
        share: Double,
        count: String,
        @ViewBuilder title: () -> Title,
        @ViewBuilder details: () -> Details
    ) {
        self.isExpanded = isExpanded
        self.toggle = toggle
        self.seconds = seconds
        self.share = share
        self.count = count
        self.title = title()
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    title
                    ShareBar(fraction: share)
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(DurationFormatter.short(seconds))
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: "\(count) · \(Int((share * 100).rounded()))%")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Hides the entries" : "Shows the entries")

            if isExpanded {
                details
                    .padding(.leading, 28)
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
            }
        }
    }
}

struct ShareBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

struct WorklogEntryActions {
    let isBusy: (Worklog) -> Bool
    let editComment: (Worklog) -> Void
    let delete: (Worklog) -> Void
}

struct WorklogEntryRow: View {
    let entry: Worklog
    /// Either a date with a time (issue breakdown) or just a time (day breakdown).
    let showsDate: Bool
    var actions: WorklogEntryActions?

    @State private var isHovered = false

    var body: some View {
        if let actions {
            let isBusy = actions.isBusy(entry)

            row(actions: actions, isBusy: isBusy)
                .opacity(isBusy ? 0.5 : 1)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .contextMenu { menuItems(actions) }
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if !isBusy {
                        Button("Edit Comment") { actions.editComment(entry) }
                        Button("Delete Entry") { actions.delete(entry) }
                    }
                }
        } else {
            row(actions: nil, isBusy: false)
        }
    }

    private func row(actions: WorklogEntryActions?, isBusy: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(leadingTitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: showsDate ? 100 : 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if !showsDate {
                    issue
                }
                comment
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DurationFormatter.short(entry.seconds))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let actions {
                actionsSlot(actions, isBusy: isBusy)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 10)
        .padding(.trailing, actions == nil ? 10 : 4)
    }

    /// Always takes its width, so the durations stay in one column whether the row is hovered or not.
    private func actionsSlot(_ actions: WorklogEntryActions, isBusy: Bool) -> some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Menu {
                    menuItems(actions)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .help("Entry actions")
            }
        }
        .frame(width: 18)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    }

    @ViewBuilder
    private func menuItems(_ actions: WorklogEntryActions) -> some View {
        Button("Edit Comment…", systemImage: "square.and.pencil") {
            actions.editComment(entry)
        }
        .disabled(actions.isBusy(entry))

        Divider()

        Button("Delete Entry…", systemImage: "trash", role: .destructive) {
            actions.delete(entry)
        }
        .disabled(actions.isBusy(entry))
    }

    private var issue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.issueKey)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.accentColor)

            if !entry.issueTitle.isEmpty {
                Text(entry.issueTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry.issueTitle)
            }
        }
    }

    @ViewBuilder
    private var comment: some View {
        if let comment = entry.comment, !comment.isEmpty {
            Text(comment)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("No comment")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var leadingTitle: String {
        let time = AppFormatters.time.string(from: entry.start)
        guard showsDate else { return time }
        return "\(AppFormatters.weekdayAndDay.string(from: entry.start)) · \(time)"
    }
}

struct WorklogEntryList: View {
    let entries: [Worklog]
    let showsDate: Bool
    var actions: WorklogEntryActions?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().padding(.leading, 10)
                }
                WorklogEntryRow(entry: entry, showsDate: showsDate, actions: actions)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
