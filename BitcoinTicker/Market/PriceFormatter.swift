import Foundation

/// Formats market values per spec §6.4. Tests pin the locale, time zone, and calendar.
struct PriceFormatter {
    let locale: Locale
    let timeZone: TimeZone
    let calendar: Calendar

    init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent) {
        self.locale = locale
        self.timeZone = timeZone
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Price, high, and low: grouping and exactly 2 decimals.
    func price(_ value: Decimal) -> String {
        number(value, decimals: 2)
    }

    /// The sign comes from the rounded value, never from the formatter: `+`, U+2212, or none.
    func change(_ value: Decimal) -> String {
        let rounded = Self.round(value, decimals: 2)
        let sign = rounded > 0 ? "+" : rounded < 0 ? "\u{2212}" : ""
        return sign + number(rounded.magnitude, decimals: 2) + "%"
    }

    func volume(_ value: Decimal) -> String {
        number(value, decimals: 0) + " BTC"
    }

    /// Local time with seconds, prefixed with the short date when `date` is not from `now`'s day.
    func updateTime(_ date: Date, now: Date) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: locale, calendar: calendar, timeZone: timeZone))
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        let day = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day())
        return "\(day), \(time)"
    }

    private func number(_ value: Decimal, decimals: Int) -> String {
        value.formatted(
            Decimal.FormatStyle(locale: locale)
                .precision(.fractionLength(decimals))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
    }

    /// Half away from zero, like the format style's rule.
    private static func round(_ value: Decimal, decimals: Int) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, decimals, .plain)
        return result
    }
}
