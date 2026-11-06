import Foundation

/// The `BTCUSDT` ticker fields v1 uses, parsed and validated per spec §5.3.
struct BinanceTickerMessage: Equatable, Sendable {
    static let symbol = "BTCUSDT"
    static let maxNumericLength = 32

    let lastPrice: Decimal
    /// Already in percentage points: `2.45` means +2.45%.
    let priceChangePercent: Decimal
    let high: Decimal
    let low: Decimal
    let volume: Decimal

    /// Returns `nil` for anything that is not a valid `BTCUSDT` ticker message.
    init?(frame: WebSocketFrame) {
        guard case .text(let text) = frame else { return nil }
        self.init(text: text)
    }

    init?(text: String) {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(text.utf8)),
              raw.s == Self.symbol,
              let lastPrice = Self.decimal(raw.c),
              let priceChangePercent = Self.decimal(raw.P),
              let high = Self.decimal(raw.h),
              let low = Self.decimal(raw.l),
              let volume = Self.decimal(raw.v),
              lastPrice > 0, high > 0, low > 0, volume >= 0
        else { return nil }
        self.lastPrice = lastPrice
        self.priceChangePercent = priceChangePercent
        self.high = high
        self.low = low
        self.volume = volume
    }

    /// A plain decimal string (spec §5.3), parsed with the period as separator in every locale.
    static func decimal(_ string: String) -> Decimal? {
        guard string.count <= maxNumericLength,
              string.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil
        else { return nil }
        return Decimal(string: string, locale: nil)
    }

    private struct Raw: Decodable {
        let s: String
        let c: String
        let P: String
        let h: String
        let l: String
        let v: String
    }
}
