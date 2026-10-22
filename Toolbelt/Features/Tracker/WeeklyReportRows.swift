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

struct WorklogEntryRow: View {
    let entry: Worklog
    /// Either a date with a time (issue breakdown) or just a time (day breakdown).
    let showsDate: Bool

    var body: some View {
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
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().padding(.leading, 10)
                }
                WorklogEntryRow(entry: entry, showsDate: showsDate)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
