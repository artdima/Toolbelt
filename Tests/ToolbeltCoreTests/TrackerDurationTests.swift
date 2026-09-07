import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Tracker durations")
struct TrackerDurationTests {
    private let hour: TimeInterval = 3600
    private var workday: TimeInterval { TrackerDuration.hoursPerWorkday * hour }
    private var workweek: TimeInterval { TrackerDuration.daysPerWorkweek * workday }

    @Test("Hours and minutes")
    func hoursAndMinutes() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT7H30M") == 7 * hour + 30 * 60)
    }

    @Test("Minutes only")
    func minutesOnly() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT45M") == 45 * 60)
    }

    /// Tracker counts a day and a week as working ones: 8 hours and 5 days.
    @Test("A working day is eight hours")
    func workdayIsEightHours() {
        #expect(TrackerDuration.seconds(fromISO8601: "P1D") == workday)
    }

    @Test("A working week is five days")
    func workweekIsFiveDays() {
        #expect(TrackerDuration.seconds(fromISO8601: "P1W") == workweek)
    }

    @Test("A composite duration")
    func compositeDuration() {
        let expected = workweek + 2 * workday + 3 * hour + 30 * 60
        #expect(TrackerDuration.seconds(fromISO8601: "P1W2DT3H30M") == expected)
    }

    /// `M` before `T` is a month, after `T` it is a minute. The classic parsing bug.
    @Test("M before T is a month, after T a minute")
    func monthVersusMinute() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT1M") == 60)
        #expect(TrackerDuration.seconds(fromISO8601: "P1M") == 4 * workweek)
    }

    @Test("A comma as the decimal separator")
    func commaAsDecimalSeparator() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT1,5H") == 1.5 * hour)
    }

    @Test("A dot as the decimal separator")
    func dotAsDecimalSeparator() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT0.5H") == 0.5 * hour)
    }

    @Test("Seconds")
    func seconds() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT90S") == 90)
    }

    @Test("Garbage parses to zero", arguments: ["", "1H", "nonsense", "T1H"])
    func garbageIsZero(input: String) {
        #expect(TrackerDuration.seconds(fromISO8601: input) == 0)
    }
}

@Suite("Duration formatting")
struct DurationFormatterTests {
    @Test("Hours and minutes")
    func hoursAndMinutes() {
        #expect(DurationFormatter.short(7 * 3600 + 30 * 60) == "7h 30m")
    }

    @Test("Hours only")
    func hoursOnly() {
        #expect(DurationFormatter.short(2 * 3600) == "2h")
    }

    @Test("Minutes only")
    func minutesOnly() {
        #expect(DurationFormatter.short(15 * 60) == "15m")
    }

    @Test("Zero and negative values")
    func zeroAndNegative() {
        #expect(DurationFormatter.short(0) == "0h")
        #expect(DurationFormatter.short(-10) == "0h")
    }

    @Test("Seconds round up to minutes")
    func secondsRoundToMinutes() {
        #expect(DurationFormatter.short(119) == "1m")
    }
}

@Suite("Pluralization")
struct PluralTests {
    @Test("One takes the singular, everything else the plural", arguments: [
        (0, "0 entries"), (1, "1 entry"), (2, "2 entries"), (21, "21 entries")
    ])
    func forms(count: Int, expected: String) {
        #expect(Plural.counted(count, "entry", "entries") == expected)
    }

    /// Irregular plurals are passed explicitly rather than guessed by appending an "s".
    @Test("An irregular plural is used as given")
    func irregularPlural() {
        #expect(Plural.counted(3, "status", "statuses") == "3 statuses")
    }
}
