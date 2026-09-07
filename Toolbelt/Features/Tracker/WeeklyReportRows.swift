//
//  WeeklyReportRows.swift
//  Toolbelt
//
//  Detail rows of the weekly report.
//

import SwiftUI

struct WorklogEntryRow: View {
    let entry: Worklog
    /// Either a date with a time (issue breakdown) or just a time (day breakdown).
    let showsDate: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(leadingTitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: showsDate ? 108 : 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if !showsDate {
                    Text(entry.issueKey)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }
                comment
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(DurationFormatter.short(entry.seconds))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var comment: some View {
        if let comment = entry.comment, !comment.isEmpty {
            Text(comment)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("No comment")
                .font(.system(size: 11))
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
                    Divider().padding(.leading, 12)
                }
                WorklogEntryRow(entry: entry, showsDate: showsDate)
            }
        }
    }
}

struct RowTotals: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .medium))
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
