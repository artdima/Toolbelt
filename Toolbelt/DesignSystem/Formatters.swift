//
//  Formatters.swift
//  Toolbelt
//
//  Форматтеры кешируются: создание DateFormatter стоит десятки микросекунд,
//  а вызовы идут по строке на каждый элемент списка при каждой перерисовке.
//

import Foundation

enum AppFormatters {
    nonisolated static let russianLocale = Locale(identifier: "ru_RU")

    /// Неделя начинается с понедельника — от этого зависит вся арифметика отчёта.
    /// nonisolated, чтобы календарь можно было использовать в значениях по умолчанию:
    /// они вычисляются вне изоляции вызывающего.
    nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = russianLocale
        return calendar
    }()

    /// «Пн, 18 авг»
    static let weekdayAndDay = dateFormatter("EE, d MMM")
    /// «10:30»
    static let time = dateFormatter("HH:mm")
    /// «18 августа»
    static let dayAndMonth = dateFormatter("d MMMM")
    /// «18 авг»
    static let shortDay = dateFormatter("d MMM")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = russianLocale
        formatter.dateFormat = format
        return formatter
    }
}

enum DurationFormatter {
    /// Секунды → «7 ч 30 м».
    static func short(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "0 ч" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 && minutes > 0 { return "\(hours) ч \(minutes) м" }
        if hours > 0 { return "\(hours) ч" }
        return "\(minutes) м"
    }
}

enum Plural {
    /// Русские правила: 1 запись, 2 записи, 5 записей.
    /// 11–14 — исключение: «одиннадцать записей», а не «запись».
    static func ru(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = abs(count) % 100
        let mod10 = abs(count) % 10

        if (11...14).contains(mod100) { return many }
        if mod10 == 1 { return one }
        if (2...4).contains(mod10) { return few }
        return many
    }

    /// «5 записей»
    static func counted(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count) \(ru(count, one, few, many))"
    }
}

extension String {
    /// Первая буква заглавная: месяцы в ru_RU приходят строчными.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
