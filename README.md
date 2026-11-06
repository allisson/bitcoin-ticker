# bitcoin-ticker
Bitcoin Ticker is a small, native macOS menu bar application that displays the live Bitcoin price for the Binance Spot BTCUSDT market.

## Development

Requirements: Xcode 26 or later (developed with Xcode 27.2), macOS 14 or later. No Apple Developer
Program membership is needed: every configuration is signed ad hoc ("Sign to Run Locally").

Open `BitcoinTicker.xcodeproj` in Xcode, or use the command line from the repository root:

```sh
# Build the Debug app into build/ (ignored by Git)
xcodebuild build -project BitcoinTicker.xcodeproj -scheme BitcoinTicker -configuration Debug -derivedDataPath build/DerivedData

# Run the tests in both test plan configurations (default and Portuguese (Brazil))
xcodebuild test -project BitcoinTicker.xcodeproj -scheme BitcoinTicker -testPlan BitcoinTicker -derivedDataPath build/DerivedData

# Launch the Debug build
open "build/DerivedData/Build/Products/Debug/Bitcoin Ticker.app"
```

The Debug build uses the bundle identifier `io.github.allisson.BitcoinTicker.debug`, so it runs
next to an installed release copy. The app has no Dock icon: quit it from its popover.

Specification and plan: [`docs/spec.md`](docs/spec.md), [`docs/roadmap.md`](docs/roadmap.md).
Guidance for coding agents: [`AGENTS.md`](AGENTS.md).
