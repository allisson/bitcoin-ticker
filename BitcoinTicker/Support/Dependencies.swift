enum Log {
    /// Constant in every configuration, so one filter matches Debug and Release (spec §9).
    static let subsystem = "io.github.allisson.BitcoinTicker"
}

/// The random source for backoff jitter (spec §5.5). The clock is injected as `any Clock<Duration>`.
protocol RandomSource: Sendable {
    /// A value in `0...1`.
    func nextUnit() -> Double
}

struct SystemRandomSource: RandomSource {
    func nextUnit() -> Double { Double.random(in: 0...1) }
}
