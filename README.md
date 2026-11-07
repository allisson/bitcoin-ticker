# Bitcoin Ticker

A small, native macOS menu bar app that shows the live Bitcoin price for the Binance Spot
`BTCUSDT` market, with its 24-hour change:

```text
₿ 67,432.18  +2.45%
```

Click it for the 24-hour high, low, and volume, the connection status, the last update time, two
preferences (Launch at login, Show 24h change in menu bar), and Quit. The app has no Dock icon and
no main window.

**The app displays exchange-provided market data. It is not a trading or investment service, and
nothing it shows is financial advice.**

## Data source

The price comes straight from Binance's public market-data WebSocket
(`wss://stream.binance.com:443/ws/btcusdt@ticker`): no API key, no account, no backend, no
analytics. The app connects only to that endpoint.

Binance does not serve every country or network. Where it rejects the connection, the popover
says "Binance is not available from your network or region", and the app retries every minute;
there is nothing to fix on the Mac. If Binance limits connections from your network, the popover
says so and the app waits at least a minute, or longer if Binance asks, before retrying.

## Requirements

macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## Install

1. Download `BitcoinTicker-<version>.dmg` from the
   [latest release](https://github.com/allisson/bitcoin-ticker/releases).
2. Optional, to check the download is intact: run `shasum -a 256 ~/Downloads/BitcoinTicker-<version>.dmg`
   in Terminal and compare the result with the checksum in the release notes. The checksum is
   published on the same page as the download, so it shows the file is intact, not who made it.
3. Open the DMG and drag **Bitcoin Ticker** to **Applications**. Do this before opening the app:
   an app opened from the DMG or from Downloads runs from a temporary read-only location, and
   Launch at login would not work.
4. Open the app from Applications. It is signed ad hoc and not notarized by Apple, so macOS blocks
   the first launch:
   - **macOS 15 or later:** macOS says "“Bitcoin Ticker.app” Not Opened". Click **Done** (not
     Move to Trash), open System Settings → Privacy & Security, scroll down, and click **Open
     Anyway** next to the message about Bitcoin Ticker, then confirm with your password or Touch
     ID. The button is offered for about an hour after the blocked launch; if it is gone, open the
     app again first. (Tested on macOS 26.)
   - **macOS 14 (not tested):** right-click (or Control-click) the app in Applications, choose **Open**, then
     **Open** again.
   - **Advanced alternative:** `xattr -dr com.apple.quarantine "/Applications/Bitcoin Ticker.app"`
     in Terminal removes the quarantine flag, so the warning is not shown.

The price appears in the menu bar, near the clock.

## Update

1. Quit Bitcoin Ticker from its popover.
2. Download the new DMG and drag the app to Applications, replacing the old copy.
3. Open it. macOS may block the first launch again: repeat step 4 of Install.
4. Open the popover and check that Launch at login shows the value you expect; if not, turn it off
   and on again.

## Uninstall

1. Open the popover and turn off **Launch at login**, so no stale login item is left behind.
2. Quit Bitcoin Ticker from its popover.
3. Delete **Bitcoin Ticker** from Applications.
4. Delete its data folder, which only holds the "Show 24h change" preference:
   `rm -rf ~/Library/Containers/io.github.allisson.BitcoinTicker`

## Troubleshooting

**The price does not appear in the menu bar.** The app is probably running but its item is
hidden:

- On a Mac with a notch, a full menu bar hides items behind the camera. Turn off **Show 24h
  change in menu bar** to shorten the item, or quit other menu bar apps to free space.
- On macOS 26 or later, open System Settings → Menu Bar and check that **Bitcoin Ticker** is
  turned on in the list of apps that can add menu bar items.
- Opening the app again does nothing while a copy is already running. If you cannot reach its
  popover, quit it from Activity Monitor (search for "Bitcoin Ticker", then Quit), and open it
  again.

**"Binance is not available from your network or region".** Binance rejects connections from your
network or country. The app retries every minute; it works again only on a network that Binance
serves.

**A warning triangle in front of the price.** The price is not current: no valid update arrived
for 30 seconds. The app reconnects on its own; the popover shows what it is doing.

## Known limitations

- Only Binance Spot `BTCUSDT`, in USDT. No other pairs, exchanges, charts, or alerts.
- Not available where Binance does not serve the network or region.
- Signed ad hoc, not notarized: every install and update needs the Gatekeeper steps above.
- Tested on macOS 26 (Apple silicon), and the Intel build only under Rosetta. Not tested on
  macOS 14, 15, or 27.

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
next to an installed release copy. Turn Launch at login off in a Debug build before deleting it:
it registers its DerivedData path.

### Release build

`CURRENT_PROJECT_VERSION` goes up by one for every published build; versions, tags, and DMG names
follow `docs/spec.md` §11.

```sh
# Universal (arm64 + x86_64) archive
xcodebuild archive -project BitcoinTicker.xcodeproj -scheme BitcoinTicker -configuration Release -archivePath build/BitcoinTicker.xcarchive ONLY_ACTIVE_ARCH=NO
APP="build/BitcoinTicker.xcarchive/Products/Applications/Bitcoin Ticker.app"

# Check: both architectures, ad hoc signature with hardened runtime, sandbox entitlements only
lipo -archs "$APP/Contents/MacOS/Bitcoin Ticker"
codesign -dv --entitlements - "$APP"

# DMG with the app and a link to /Applications
rm -rf build/dmg && mkdir -p build/dmg && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "Bitcoin Ticker" -srcfolder build/dmg -format UDZO build/BitcoinTicker-<version>.dmg
shasum -a 256 build/BitcoinTicker-<version>.dmg
```

Specification and plan: [`docs/spec.md`](docs/spec.md), [`docs/roadmap.md`](docs/roadmap.md).
Guidance for coding agents: [`AGENTS.md`](AGENTS.md).

## License

[MIT](LICENSE)
