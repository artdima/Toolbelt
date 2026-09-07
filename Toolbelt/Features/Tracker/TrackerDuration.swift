//
//  TrackerDuration.swift
//  Toolbelt
//

import Foundation

/// Parsing Tracker durations and dates. Pure functions with no dependencies —
/// every piece of non-obvious arithmetic in the project lives here and is tested.
enum TrackerDuration {
    /// Tracker counts a day and a week as working ones.
    static let hoursPerWorkday: Double = 8
    static let daysPerWorkweek: Double = 5

    private static let secondsPerHour: TimeInterval = 3600
    private static let monthsPerYear: Double = 12
    private static let weeksPerMonth: Double = 4

    /// Parses an ISO 8601 duration such as `P1W2DT3H30M` into seconds.
    /// `M` before `T` means months, after `T` it means minutes.
    static func seconds(fromISO8601 string: String) -> TimeInterval {
        var value = Substring(string)
        guard value.first == "P" else { return 0 }
        value = value.dropFirst()

        let workday = hoursPerWorkday * secondsPerHour
        let workweek = daysPerWorkweek * workday
        let workmonth = weeksPerMonth * workweek

        var seconds: TimeInterval = 0
        var isTimePart = false
        var number = ""

        for character in value {
            if character == "T" {
                isTimePart = true
                number = ""
                continue
            }
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }

            let amount = Double(number) ?? 0
            number = ""

            switch character {
            case "Y": seconds += amount * monthsPerYear * workmonth
            case "W": seconds += amount * workweek
            case "D": seconds += amount * workday
            case "H": seconds += amount * secondsPerHour
            case "S": seconds += amount
            case "M": seconds += isTimePart ? amount * 60 : amount * workmonth
            default: break
            }
        }
        return seconds
    }
}

enum TrackerDate {
    private static let withMilliseconds = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
    private static let withSeconds = formatter("yyyy-MM-dd'T'HH:mm:ssZ")
    /// A deadline arrives without a time component.
    private static let dayOnly = formatter("yyyy-MM-dd")

    static func parse(_ string: String) -> Date? {
        withMilliseconds.date(from: string)
            ?? withSeconds.date(from: string)
            ?? dayOnly.date(from: string)
    }

    static func string(from date: Date) -> String {
        withMilliseconds.string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
