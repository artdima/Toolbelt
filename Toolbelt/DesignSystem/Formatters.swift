//
//  Formatters.swift
//  Toolbelt
//
//  Formatters are cached: building a DateFormatter costs tens of microseconds and
//  these are called once per row on every redraw.
//

import Foundation

enum AppFormatters {
    /// POSIX on purpose: with a fixed `dateFormat` and any other locale the user's
    /// 12/24-hour system setting silently rewrites the format (QA1480).
    nonisolated static let locale = Locale(identifier: "en_US_POSIX")

    /// Weeks start on Monday — that is a Tracker rule, not a locale preference,
    /// and the whole weekly report depends on it.
    /// `nonisolated` so the calendar can be used in default argument values:
    /// those are evaluated outside the caller's isolation.
    nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = locale
        return calendar
    }()

    /// "Mon, 18 Aug"
    static let weekdayAndDay = dateFormatter("EEE, d MMM")
    /// "10:30"
    static let time = dateFormatter("HH:mm")
    /// "September 18"
    static let monthAndDay = dateFormatter("MMMM d")
    /// "Sep 18"
    static let shortDay = dateFormatter("MMM d")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter
    }
}

enum DurationFormatter {
    /// Seconds to "7h 30m".
    static func short(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "0h" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    /// Seconds to "184 ms" or "1.3 s".
    static func milliseconds(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "\(Int((seconds * 1000).rounded())) ms" }
        return String(format: "%.1f s", seconds)
    }
}

enum ByteFormatter {
    /// Bytes to "512 B", "4.2 KB", "2.9 MB".
    static func short(_ count: Int) -> String {
        let kilobyte = 1024.0
        let value = Double(count)
        if value < kilobyte { return "\(count) B" }
        if value < kilobyte * kilobyte { return String(format: "%.1f KB", value / kilobyte) }
        return String(format: "%.1f MB", value / kilobyte / kilobyte)
    }
}

enum Plural {
    /// "1 entry" / "3 entries". Irregular plurals are passed explicitly rather than
    /// guessed by appending an "s".
    static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

extension String {
    /// Uppercases the first character, leaving the rest untouched.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
