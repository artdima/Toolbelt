import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Relative time")
struct RelativeTimeTests {
    /// UTC so the tests do not depend on the machine time zone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Thursday, 15 October 2026, 15:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 15))!
    }

    private func short(secondsAgo: TimeInterval) -> String {
        RelativeTimeFormatter.short(now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar)
    }

    @Test("Under a minute is just now")
    func justNow() {
        #expect(short(secondsAgo: 0) == "Just now")
        #expect(short(secondsAgo: 59) == "Just now")
    }

    @Test("Minutes within the hour")
    func minutes() {
        #expect(short(secondsAgo: 12 * 60) == "12 min ago")
    }

    @Test("Hours within the same day")
    func hours() {
        #expect(short(secondsAgo: 3 * 3600) == "3 h ago")
    }

    @Test("The previous calendar day is yesterday")
    func yesterday() {
        #expect(short(secondsAgo: 20 * 3600) == "Yesterday")
    }

    @Test("Older dates show the day")
    func olderDates() {
        let date = now.addingTimeInterval(-5 * 86_400)
        #expect(RelativeTimeFormatter.short(date, now: now, calendar: calendar) == AppFormatters.shortDay.string(from: date))
    }

    @Test("A date in the future is just now")
    func futureDate() {
        #expect(short(secondsAgo: -30) == "Just now")
    }
}
