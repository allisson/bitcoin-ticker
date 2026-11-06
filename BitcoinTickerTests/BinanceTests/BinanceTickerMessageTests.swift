import Foundation
import Testing
@testable import BitcoinTicker

struct BinanceTickerMessageTests {
    /// A Binance `@ticker` payload with the fields v1 ignores too.
    static func payload(
        s: String = "\"BTCUSDT\"", c: String = "\"67432.18\"", P: String = "\"2.45\"",
        h: String = "\"68000.00\"", l: String = "\"65000.50\"", v: String = "\"12345.678\""
    ) -> String {
        """
        {"e":"24hrTicker","E":1700000000000,"s":\(s),"p":"1612.18","P":\(P),"w":"66500.00",\
        "c":\(c),"Q":"0.001","o":"65820.00","h":\(h),"l":\(l),"v":\(v),"q":"820000000.00",\
        "O":1699913600000,"C":1700000000000,"F":1,"L":2,"n":2}
        """
    }

    static func decimal(_ significand: UInt64, exponent: Int, negative: Bool = false) -> Decimal {
        Decimal(sign: negative ? .minus : .plus, exponent: exponent, significand: Decimal(significand))
    }

    @Test func parsesValidPayload() throws {
        let message = try #require(BinanceTickerMessage(frame: .text(Self.payload())))
        #expect(message.lastPrice == Self.decimal(6743218, exponent: -2))
        #expect(message.priceChangePercent == Self.decimal(245, exponent: -2))
        #expect(message.high == Self.decimal(68000, exponent: 0))
        #expect(message.low == Self.decimal(650005, exponent: -1))
        #expect(message.volume == Self.decimal(12345678, exponent: -3))
    }

    @Test func keepsPercentInPercentagePoints() throws {
        let message = try #require(BinanceTickerMessage(text: Self.payload(P: "\"2.45\"")))
        #expect(message.priceChangePercent == Self.decimal(245, exponent: -2))
    }

    @Test func acceptsNegativePercentAndZeroVolume() throws {
        let message = try #require(BinanceTickerMessage(text: Self.payload(P: "\"-3.10\"", v: "\"0\"")))
        #expect(message.priceChangePercent == Self.decimal(310, exponent: -2, negative: true))
        #expect(message.volume == 0)
    }

    @Test func rejectsBinaryFrame() {
        #expect(BinanceTickerMessage(frame: .binary(Data(Self.payload().utf8))) == nil)
    }

    @Test(arguments: ["", "not json", "[]", "{}", "{\"s\":\"BTCUSDT\"}"])
    func rejectsInvalidOrIncompleteJSON(text: String) {
        #expect(BinanceTickerMessage(text: text) == nil)
    }

    @Test func rejectsMissingField() {
        let text = Self.payload().replacingOccurrences(of: "\"h\":\"68000.00\",", with: "")
        #expect(!text.contains("\"h\":"))
        #expect(BinanceTickerMessage(text: text) == nil)
    }

    @Test func rejectsNumberInsteadOfString() {
        #expect(BinanceTickerMessage(text: Self.payload(c: "67432.18")) == nil)
    }

    @Test(arguments: ["\"ETHUSDT\"", "\"btcusdt\"", "\"\""])
    func rejectsUnexpectedSymbol(symbol: String) {
        #expect(BinanceTickerMessage(text: Self.payload(s: symbol)) == nil)
    }

    @Test(arguments: ["12abc", "12\n", "1e5", "+1", ".5", "5.", "", "NaN", "inf", "1,5", " 1", "1 ", "--1", "١٢"])
    func rejectsNonPlainDecimal(value: String) {
        #expect(BinanceTickerMessage.decimal(value) == nil)
    }

    @Test func rejectsGarbageSuffixInPayload() {
        #expect(BinanceTickerMessage(text: Self.payload(c: "\"12abc\"")) == nil)
        #expect(BinanceTickerMessage(text: Self.payload(c: "\"12\\n\"")) == nil)
    }

    @Test func enforcesLengthLimit() throws {
        let accepted = "1." + String(repeating: "5", count: 30)
        let rejected = accepted + "5"
        #expect(accepted.count == 32)
        #expect(rejected.count == 33)
        #expect(BinanceTickerMessage.decimal(accepted) != nil)
        #expect(BinanceTickerMessage.decimal(rejected) == nil)
    }

    @Test(arguments: [
        payload(c: "\"0\""), payload(c: "\"-1.00\""), payload(h: "\"0.00\""), payload(l: "\"-5\""),
        payload(v: "\"-0.1\""), payload(c: "\"NaN\""),
    ])
    func rejectsOutOfRangeValues(text: String) {
        #expect(BinanceTickerMessage(text: text) == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EXPECT_COMMA_DECIMAL"] == "1"))
    func parsesUnderCommaDecimalLocale() throws {
        try #require(Locale.current.decimalSeparator == ",")
        let message = try #require(BinanceTickerMessage(text: Self.payload()))
        #expect(message.lastPrice == Self.decimal(6743218, exponent: -2))
        #expect(message.priceChangePercent == Self.decimal(245, exponent: -2))
    }
}
