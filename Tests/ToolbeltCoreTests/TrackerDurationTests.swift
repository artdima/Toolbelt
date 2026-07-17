import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Длительности Трекера")
struct TrackerDurationTests {
    private let hour: TimeInterval = 3600
    private var workday: TimeInterval { TrackerDuration.hoursPerWorkday * hour }
    private var workweek: TimeInterval { TrackerDuration.daysPerWorkweek * workday }

    @Test("Часы и минуты")
    func hoursAndMinutes() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT7H30M") == 7 * hour + 30 * 60)
    }

    @Test("Только минуты")
    func minutesOnly() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT45M") == 45 * 60)
    }

    /// День и неделя в Трекере рабочие: 8 часов и 5 дней.
    @Test("Рабочий день — восемь часов")
    func workdayIsEightHours() {
        #expect(TrackerDuration.seconds(fromISO8601: "P1D") == workday)
    }

    @Test("Рабочая неделя — пять дней")
    func workweekIsFiveDays() {
        #expect(TrackerDuration.seconds(fromISO8601: "P1W") == workweek)
    }

    @Test("Составная длительность")
    func compositeDuration() {
        let expected = workweek + 2 * workday + 3 * hour + 30 * 60
        #expect(TrackerDuration.seconds(fromISO8601: "P1W2DT3H30M") == expected)
    }

    /// `M` до `T` — месяцы, после `T` — минуты. Классическая ошибка разбора.
    @Test("M до T — месяц, после T — минута")
    func monthVersusMinute() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT1M") == 60)
        #expect(TrackerDuration.seconds(fromISO8601: "P1M") == 4 * workweek)
    }

    @Test("Запятая как десятичный разделитель")
    func commaAsDecimalSeparator() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT1,5H") == 1.5 * hour)
    }

    @Test("Точка как десятичный разделитель")
    func dotAsDecimalSeparator() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT0.5H") == 0.5 * hour)
    }

    @Test("Секунды")
    func seconds() {
        #expect(TrackerDuration.seconds(fromISO8601: "PT90S") == 90)
    }

    @Test("Мусор даёт ноль", arguments: ["", "1H", "нет", "T1H"])
    func garbageIsZero(input: String) {
        #expect(TrackerDuration.seconds(fromISO8601: input) == 0)
    }
}

@Suite("Формат длительности")
struct DurationFormatterTests {
    @Test("Часы и минуты")
    func hoursAndMinutes() {
        #expect(DurationFormatter.short(7 * 3600 + 30 * 60) == "7 ч 30 м")
    }

    @Test("Только часы")
    func hoursOnly() {
        #expect(DurationFormatter.short(2 * 3600) == "2 ч")
    }

    @Test("Только минуты")
    func minutesOnly() {
        #expect(DurationFormatter.short(15 * 60) == "15 м")
    }

    @Test("Ноль и отрицательное значение")
    func zeroAndNegative() {
        #expect(DurationFormatter.short(0) == "0 ч")
        #expect(DurationFormatter.short(-10) == "0 ч")
    }

    @Test("Секунды округляются до минут")
    func secondsRoundToMinutes() {
        #expect(DurationFormatter.short(119) == "1 м")
    }
}

@Suite("Русская плюрализация")
struct PluralTests {
    @Test("Формы по последней цифре", arguments: [
        (1, "запись"), (2, "записи"), (4, "записи"), (5, "записей"),
        (21, "запись"), (22, "записи"), (25, "записей"),
        (101, "запись"), (0, "записей")
    ])
    func basicForms(count: Int, expected: String) {
        #expect(Plural.ru(count, "запись", "записи", "записей") == expected)
    }

    /// 11–14 — исключение: «одиннадцать записей», а не «запись».
    @Test("Числа 11–14 всегда во множественном числе", arguments: [11, 12, 13, 14, 111, 112])
    func teensAreAlwaysMany(count: Int) {
        #expect(Plural.ru(count, "запись", "записи", "записей") == "записей")
    }

    @Test("Число подставляется в строку")
    func countedIncludesNumber() {
        #expect(Plural.counted(3, "задача", "задачи", "задач") == "3 задачи")
    }
}
