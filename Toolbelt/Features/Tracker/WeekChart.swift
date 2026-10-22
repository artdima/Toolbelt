//
//  WeekChart.swift
//  Toolbelt
//
//  Time logged per day as vertical bars, with the workday as the reference line.
//

import SwiftUI

struct WeekChart: View {
    let days: [WeekReport.Day]

    private let plotHeight: CGFloat = 80
    private let labelHeadroom: CGFloat = 18
    private let axisWidth: CGFloat = 26
    private let barWidth: CGFloat = 18
    private let gridHours = [4, 8]

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                ForEach(gridHours, id: \.self) { hours in
                    gridLine(hours)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.16))
                    .frame(height: 1)
                    .padding(.leading, axisWidth)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(days) { day in
                        bar(day)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.leading, axisWidth)
            }
            .frame(height: plotHeight + labelHeadroom)

            HStack(alignment: .top, spacing: 0) {
                ForEach(days) { day in
                    dayLabel(day)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, axisWidth)
        }
    }

    private func gridLine(_ hours: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(hours)h")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: axisWidth - 6, alignment: .trailing)
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
        // A zero-height frame puts the line itself, not the label box, at the offset.
        .frame(height: 0)
        .offset(y: -barHeight(TimeInterval(hours) * 3600))
    }

    private func bar(_ day: WeekReport.Day) -> some View {
        VStack(spacing: 3) {
            if day.seconds > 0 {
                Text(DurationFormatter.short(day.seconds))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .fixedSize()
            }
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                .fill(barColor(day.seconds))
                .frame(width: barWidth, height: max(2, barHeight(day.seconds)))
        }
    }

    private func dayLabel(_ day: WeekReport.Day) -> some View {
        let isToday = AppFormatters.calendar.isDateInToday(day.date)

        return VStack(spacing: 1) {
            Text(AppFormatters.weekday.string(from: day.date))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(AppFormatters.dayOfMonth.string(from: day.date))
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
            Circle()
                .fill(isToday ? Color.accentColor : .clear)
                .frame(width: 4, height: 4)
        }
    }

    /// The scale stretches past the workday only when some day runs over it.
    private var scaleSeconds: TimeInterval {
        max(TrackerDuration.workdaySeconds, days.map(\.seconds).max() ?? 0)
    }

    private func barHeight(_ seconds: TimeInterval) -> CGFloat {
        plotHeight * CGFloat(seconds / scaleSeconds)
    }

    private func barColor(_ seconds: TimeInterval) -> Color {
        if seconds == 0 { return Color.primary.opacity(0.07) }
        return seconds > TrackerDuration.workdaySeconds ? .red : .accentColor
    }
}
