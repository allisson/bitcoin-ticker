import Foundation
import Testing
@testable import BitcoinTicker

struct PriceFormatterTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func formatter(_ locale: String) -> PriceFormatter {
        PriceFormatter(locale: Locale(identifier: locale), timeZone: utc, calendar: Calendar(identifier: .gregorian))
    }

    static func date(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    let us = Self.formatter("en_US")

    @Test(arguments: [
        ("67432.18", "67,432.18"), ("67432.185", "67,432.19"), ("67432.1", "67,432.10"), ("0.5", "0.50"),
    ])
    func price(input: String, expected: String) {
        #expect(us.price(Decimal(string: input)!) == expected)
    }

    @Test(arguments: [
        ("2.45", "+2.45%"), // already in percentage points: not multiplied by 100
        ("-3.10", "\u{2212}3.10%"),
        ("-0.004", "0.00%"),
        ("0", "0.00%"),
        ("-2.455", "\u{2212}2.46%"),
        ("2.455", "+2.46%"),
    ])
    func change(input: String, expected: String) {
        #expect(us.change(Decimal(string: input)!) == expected)
    }

    @Test func volumeHasNoDecimalsAndABTCSuffix() {
        #expect(us.volume(Decimal(string: "12345.5")!) == "12,346 BTC")
    }

    @Test func commaDecimalLocale() {
        let br = Self.formatter("pt_BR")
        #expect(br.price(Decimal(string: "67432.18")!) == "67.432,18")
        #expect(br.change(Decimal(string: "2.45")!) == "+2,45%")
        #expect(br.change(Decimal(string: "-2.455")!) == "\u{2212}2,46%")
        #expect(br.volume(Decimal(string: "12345")!) == "12.345 BTC")
    }

    @Test func updateTimeFollowsTheLocaleHourCycle() {
        let update = Self.date("2026-11-05T14:32:07Z")
        let now = Self.date("2026-11-05T18:00:00Z")
        #expect(us.updateTime(update, now: now) == "2:32:07\u{202F}PM")
        #expect(Self.formatter("en_GB").updateTime(update, now: now) == "14:32:07")
    }

    @Test func updateFromBeforeMidnightCheckedAfterItGetsTheDate() {
        let update = Self.date("2026-11-05T23:59:50Z")
        let now = Self.date("2026-11-06T00:00:10Z")
        #expect(us.updateTime(update, now: now) == "Nov 5, 11:59:50\u{202F}PM")
        #expect(Self.formatter("en_GB").updateTime(update, now: now) == "5 Nov, 23:59:50")
        #expect(Self.formatter("en_GB").updateTime(update, now: update) == "23:59:50")
    }
}
