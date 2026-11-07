# Bitcoin Ticker for macOS — v1 Roadmap

**Roadmap status:** Reviewed, ready to start  
**Scope:** First lean release (v1.0)  
**Primary outcome:** A reliable native macOS menu bar app showing Binance Spot `BTCUSDT` in real time.

## 1. Release objective

Deliver the v1.0 described in `spec.md`: a native menu bar utility that shows the live Binance Spot `BTCUSDT` price and 24-hour change, recovers from network loss and sleep, and needs no API key, account, backend, or paid service.

Anything not needed to meet this objective is out of scope for v1.

## 2. Scope

`spec.md` is the single source of scope and behavior. This roadmap does not repeat it, so the two documents cannot drift apart: milestone items name what to build and point to the spec section that defines it; only the test lists and the manual verifications carry detail. The risk table (§6) lists only the risks that need a verification, a decision, or user-facing documentation; where it differs from the spec, the spec wins.

- Included: spec §2.1 (goals) and §12 (acceptance criteria).
- Excluded: spec §2.2 (non-goals) and §6.3 (settings not to add).

## 3. Milestones

The estimates below are planning estimates for one developer and assume familiarity with Swift and Xcode. They are not deadlines.

Write the tests for each milestone in the same milestone as the code they cover.

### Milestone 0 — Project foundation

**Estimate:** 0.5–1 day

- [x] Create the macOS application project.
- [x] Use Xcode 26 or later. Set the minimum deployment target to macOS 14, Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` (set explicitly), and a Swift Testing test target (spec §4).
- [x] Configure app identity, bundle identifier (`io.github.allisson.BitcoinTicker`, spec §4), and versioning (`MARKETING_VERSION = 1.0.0`, `CURRENT_PROJECT_VERSION = 1`; spec §11). Set `PRODUCT_NAME` and `PRODUCT_MODULE_NAME` per spec §4. Give the Debug configuration a `.debug` suffix on `PRODUCT_BUNDLE_IDENTIFIER`: otherwise the single-instance check (spec §7) quits a Debug build launched from Xcode while the installed app runs, and the two builds share `UserDefaults` and the `SMAppService` registration. Release keeps the plain identifier, so the M4 second-copy check is unaffected.
- [x] Set `INFOPLIST_KEY_LSUIElement = YES` (no Dock icon; no separate Info.plist file, spec §4).
- [x] Enable App Sandbox with only the `com.apple.security.network.client` entitlement, and enable hardened runtime. Remove the read-only user-selected files access the Xcode template enables (`ENABLE_USER_SELECTED_FILES`, spec §10).
- [x] Create the initial source and test groups, and the test plan (spec §8).
- [x] When the process is a unit-test host, skip the `MarketDataStore` and the single-instance check, and do not insert the menu bar item (`MenuBarExtra(isInserted:)` bound to `false`; spec §7). Verify which signal detects the host under both test plan configurations, and record it in the verification log (§9). Check: launch the Debug `.app` outside Xcode (Finder or `open`; Xcode stops the running app of the scheme before it runs tests), then run the suite with `xcodebuild test` from the terminal; it runs to the end and shows no second menu bar item. The WebSocket check comes in M1, once the app starts the client.
- [x] Add the app icon (`AppIcon` asset; spec §11).
- [x] Allow a single instance: quit at launch if another instance with the same bundle identifier and an earlier `launchDate` is running, excluding the current process from the list, and insert the menu bar item only after the check passes (spec §7). Keep the decision in a pure function and test it: another instance launched earlier (quit), later (stay), at the same `launchDate` or with a `nil` date (the higher `processIdentifier` quits), and only the current process in the list (stay).
- [x] Add a `MenuBarExtra` entry point with `.menuBarExtraStyle(.window)`.
- [x] Add a basic menu bar label and a popover placeholder with a Quit button.
- [x] Verify that the `MenuBarExtra` label renders a composite label (status symbol, price, percentage) and honors `.monospacedDigit()`. If not, switch to a template image rendered with `ImageRenderer` (spec §6.1). Record the result in the verification log (§9).
- [x] Expand the existing README with the development setup.
- [x] Set signing to "Sign to Run Locally" (ad hoc) for every configuration; no Apple Developer Program membership is needed (spec §11).
- [x] Add continuous integration: a GitHub Actions workflow (`.github/workflows/ci.yml`) that runs the test plan, in both configurations, on every pull request to `main` and every push to `main`. Use the `macos-26` runner with Xcode 26, the oldest major version spec §4 allows, so the project keeps building with it while development uses a newer Xcode.

**Exit criteria:** The app builds and launches without a Dock icon, its menu bar item opens a popover, Quit closes the app, and CI passes.

### Milestone 1 — Binance WebSocket client

**Estimate:** 1–2 days

Message model and parser first (implementation order step 2):

- [x] Implement `BinanceTickerMessage`: decode, validate, and parse the required fields (spec §5.3).
- [x] Add tests for valid, invalid, incomplete, and unexpected-symbol payloads, for numeric strings with a garbage suffix (`"12abc"`) or a trailing newline (`"12\n"`), for the length limit (a 32-character value accepted, a 33-character value rejected), for other forms the pattern must reject (`"1e5"`, which `Decimal(string:locale:)` accepts, `"+1"`, `".5"`, `"5."`, `""`), for out-of-range values (NaN, zero or negative price, negative volume), for accepted edge values (zero volume, negative `P`), for `P` in percentage points, for a binary frame, and for parsing under a comma-decimal locale (`pt_BR`, through a test plan configuration with language Portuguese (Brazil), region Brazil, and `EXPECT_COMMA_DECIMAL=1`; the test runs only when that variable is set, and first asserts that `Locale.current.decimalSeparator` is `","`, spec §5.3).

Then transport, connection, and receive loop (step 3):

- [x] Define the WebSocket transport protocol, the injectable clock, and the injectable random source (spec §5.5). The transport reports handshake completion and failure from the session delegate callbacks, not from `receive()`.
- [x] Write a manual test clock in the test target (no third-party package).
- [x] Implement `BinanceWebSocketClient` as an actor using `URLSessionWebSocketTask` behind that protocol.
- [x] Connect to `wss://stream.binance.com:443/ws/btcusdt@ticker`.
- [x] Add the Debug-only launch-argument override for the connection URL (`-BinanceURL`; spec §5.5). Release builds ignore it.
- [x] Start the client from the app for the development build, behind the same unit-test-host guard as the store (spec §7); M2b moves this into `MarketDataStore`. Check, with the M0 procedure (Debug app launched outside Xcode, suite run with `xcodebuild test`): the test suite opens no WebSocket connection (the test process logs no connection-state change). Record the result in the verification log (§9).
- [x] Implement a single, cancellable receive loop.
- [x] Define the connection states from spec §5.7 and surface them, with parsed ticker events, through a testable interface.
- [x] Map rejected handshakes by HTTP status to a connection state (spec §5.2, §5.7). Which delay follows each case is implemented in M2a.
- [x] Manual verification, done once and not part of the automated suite: check that the status and the `Retry-After` header are readable from the task's `response`, against a local test server on `ws://127.0.0.1` (ATS does not apply to IP addresses, so no ATS exception is needed; spec §10). Run the server as a separate process outside the app, for example a small local script: the app is sandboxed, and a listener inside it would need `com.apple.security.network.server`, which spec §10 does not allow. Point a Debug build at the server with `-BinanceURL`; the server rejects the WebSocket upgrade with 451 and with 429 plus `Retry-After` (a VPN exiting in a blocked region also works for 451). Record the result in the verification log (§9); if either is not readable, record the limitation there too (spec §5.2). The automated suite covers the mapping through the fake transport (below).
- [x] Verify that `URLSessionWebSocketTask` answers Binance's server pings. Keep a connection open for at least 5 minutes (pings every 20 s, pong timeout 60 s): if Binance does not close it, pongs are being sent. If it is closed, replace the transport implementation with `NWConnection` and `NWProtocolWebSocket` (`URLSessionWebSocketTask` cannot send a pong; spec §5.5) and repeat the status and `Retry-After` check above on it. Record which transport was kept in the verification log (§9).
- [x] Decide the endpoint at build time (spec §5.2): keep `stream.binance.com` unless it fails any of the handshake, payload, or ping/pong checks and `data-stream.binance.vision` passes all of them. Record the decision in the verification log (§9).
- [x] Handle malformed messages and transport errors without crashing: discard a malformed message and keep the connection open, logging only the first one per connection (spec §5.5).
- [x] Add structured local logging with `Logger` for actionable diagnostics, including every connection-state change at `.notice` with `privacy: .public` on the state name, and ticker messages only at `.debug`, without repeating the same failure at high frequency (spec §5.5, §9). Freshness transitions are logged by the store in M2b.
- [x] Add tests, with the fake transport, for the handshake status mapping of 451, 403, 429, and 418; the full table, including another 4xx/5xx and an unreadable status, as a pure-function test.

**Exit criteria:** Unit tests pass using a fake transport, and a development build logs live `BTCUSDT` ticker updates from Binance (at `.debug`, visible with `log stream --level debug --predicate 'subsystem == "io.github.allisson.BitcoinTicker"'`; spec §9).

### Milestone 2a — Client resilience

**Estimate:** to be set at the end of M1, with the transport in hand. M2a and M2b hold the project's state machine and most of its tests, so they are likely the longest milestones.

In the client (`BinanceWebSocketClient`, spec §7):

Implement each rule of spec §5.5, with every interval injectable:

- [x] Handshake timeout.
- [x] Backoff with full jitter.
- [x] Fixed delay after 451/403/429/418, including `Retry-After`, the reset of k, and its behavior while Offline.
- [x] Minimum attempt interval between attempt starts.
- [x] Backoff reset once the connection is stable.
- [x] Single connection and receive loop; messages from a closed or replaced connection are discarded.
- [x] `reconnect()` and `setNetworkAvailable(_:)`.
- [x] Unavailable and Rate limited kept during the attempt after their fixed delay (spec §5.7).
- [x] Cancellation: closing the client cancels the connection, the receive loop, and every pending delay.

Tests, using the fake transport, clock, and random source:

- [x] State transitions, including Connecting for the first attempt after starting Offline and for retries (and their backoff wait) before the first handshake.
- [x] `setNetworkAvailable(true)` leaving Offline and starting an attempt (Connecting before the first handshake, Reconnecting after).
- [x] A 451 on the first attempt, then Offline, then the path returning during the fixed delay: the state is Unavailable, not Connecting.
- [x] A fixed delay that ends while Offline, then the path returning before the following attempt has run (spec §5.5, §5.7): Unavailable after a 451 on the first attempt, Rate limited after a 429 on the first attempt, never Connecting.
- [x] `setNetworkAvailable(false)` during an in-flight handshake: the attempt is abandoned and the state is Offline.
- [x] `reconnect()` during a pending backoff delay starting an attempt as soon as the minimum attempt interval allows, without incrementing k.
- [x] Minimum attempt interval: a path flapping between unavailable and available every 0.5 s, and repeated `reconnect()` calls, never start two attempts less than the interval apart; several `reconnect()` calls while an attempt waits for the interval start exactly one attempt.
- [x] Leaving Offline does not change k.
- [x] A 429 on the very first attempt giving Rate limited, not Connecting (spec §5.7).
- [x] A rejection with another 4xx/5xx and with an unreadable status, through the fake transport: Connecting before the first handshake, Reconnecting after, followed by the backoff delay for k.
- [x] `setNetworkAvailable(false)` closing a connection before the stability interval does not increment k.
- [x] A `reconnect()` closing a connection before the stability interval does not increment k.
- [x] `reconnect()` during an in-flight handshake doing nothing.
- [x] `reconnect()` during a pending fixed delay not shortening it.
- [x] The fixed delay counting through Offline, and the previous state restored when the path returns.
- [x] Handshake timeout.
- [x] Unavailable kept during the retry after a 451/403 fixed delay, and Rate limited during the retry after a 429/418 one; a 429/418 on the retry after a 451/403 delay giving Rate limited with a new fixed delay, and a 451/403 on the retry after a 429/418 delay giving Unavailable.
- [x] Backoff bounds and reset; no reset when a connection delivers a message and closes before the stability interval (k keeps growing).
- [x] Fixed delay with, without, with a non-numeric, with a shorter-than-60 s (waits 60 s), with a longer-than-3-days (waits 3 days), and with a digits-only value too large for an integer (waits 3 days) `Retry-After`.
- [x] Backoff from k = 1 when the attempt after a 451/403 or a 429/418 fixed delay fails for another reason, and when it connects and closes before the stability interval (k was above 1 before the delay).
- [x] A server close after a stable connection (Binance's 24-hour close) reconnecting after the k = 1 backoff delay (at most 1 s).
- [x] Cancellation.
- [x] Absence of duplicate connections.
- [x] A message delivered by a connection after it was closed or replaced emits no ticker event.
- [x] A malformed message (invalid JSON, binary frame, unexpected symbol) emits no ticker event and does not close the connection; repeated malformed messages log once per connection.

**Exit criteria:** The client handles disconnects (including the 24-hour close), rejections, and network loss predictably, without duplicate connections or tight reconnect loops, and all of it is covered by tests.

### Milestone 2b — Market data state

**Estimate:** to be set at the end of M1, together with M2a.

In the store (`MarketDataStore`, spec §7):

- [x] Implement `MarketDataStore` (`@MainActor`, `@Observable`; spec §7), with connection state and data freshness as separate dimensions (spec §5.7).
- [x] Receive times on the injected clock and wall-clock `now` source, and the centralized freshness threshold (spec §5.6).
- [x] Connection watchdog (spec §5.6).
- [x] One long-lived deadline task, which waits for a store signal when no deadline is pending (spec §5.6).
- [x] Path and wake sources behind small protocols, calling `client.setNetworkAvailable(_:)` and `client.reconnect()` per spec §5.5.
- [x] Log every data-freshness transition (spec §9).
- [x] Shutdown and task cancellation.
- [x] Repeat the M1 test-host check now that the store starts the client, with the M0 procedure: the test suite opens no WebSocket connection (spec §7). Record the result in the verification log (§9).

Tests, using the real client over the fake transport, clock, and random source, plus fake path/wake sources:

- [x] Freshness, including Live turning Stale with no further messages, and Stale right after a clock jump that stands in for sleep.
- [x] Watchdog on an established connection that delivered messages and then went silent: one reconnect, k unchanged.
- [x] Watchdog: no reconnect right after a handshake that follows a long outage; a reconnect when a new connection never sends data.
- [x] Price staying Live through a 24-hour close followed by a reconnect within the threshold.
- [x] Deadline task with nothing pending: the first handshake since launch, and a handshake after the data has turned Stale, followed by silence, each produce one watchdog reconnect.
- [x] No watchdog reconnect while Connecting, Reconnecting, Rate limited, Unavailable, or Offline.
- [x] Path return and wake not shortening a fixed delay.
- [x] No reconnect on the initial satisfied path report or on an interface change.
- [x] An initial unsatisfied path report, and a later path loss, each giving Offline.
- [x] Wake while Connected calling `client.reconnect()`.
- [x] A `.requiresConnection` path counts as available: no Offline, attempts continue (spec §5.5).
- [x] Wake while Offline starting no attempt.
- [x] Shutdown cancelling the deadline task and the client.

**Exit criteria:** The store handles half-open connections, stale data, network-path changes, and wake predictably, without bypassing a fixed delay, and all of it is covered by tests.

### Milestone 3 — Menu bar and popover UI

**Estimate:** 1–2 days

- [x] Implement `PriceFormatter` per spec §6.4, with tests in a pinned locale: `P` not multiplied by 100, the sign prefixed by the formatter code (U+2212 for negatives, never the locale's own sign), `"-0.004"` shown as `0.00%` without a sign, half-away-from-zero rounding (`"-2.455"` → `−2.46%`), locale-aware grouping (including a comma-decimal locale, where the change reads `+2,45%`), volume with 0 decimals and ` BTC` after a space, and the update time with seconds in a 12-hour locale (`en_US`) and a 24-hour locale (`en_GB`), with the date prefix when the update is not from today (injected `now`). Tests cannot change the user's 12/24-hour setting, so the locale stands in for it. Pin the time zone and calendar too, and cover an update shortly before midnight checked shortly after it.
- [x] Implement the status text as a pure function of connection state and data freshness (spec §6.2), with a table test covering every row of the spec's status table and the stale note.
- [x] Implement the compact menu bar label with monospaced digits.
- [x] Display the latest BTC/USDT price.
- [x] Display the 24-hour percentage change with an explicit sign (no color in the menu bar; spec §6.1).
- [x] Show the stale status symbol in the menu bar itself, and a placeholder before the first price.
- [x] Implement the popover market summary.
- [x] Display 24-hour high, low, and BTC volume, with `—` for every market value before the first price (spec §6.2).
- [x] Display Binance Spot market identity.
- [x] Display connection state and data freshness with the status text from spec §6.2, and the last successful update time.
- [x] Implement the Connecting, Reconnecting, Rate limited, Offline, Unavailable, and stale presentations (spec §6.2).
- [ ] Check layout in light and dark appearances, on the current macOS release (macOS 27), including the translucent menu bar introduced in macOS 26. Record the result in the verification log (§9); M5 compares macOS 14 against it.
- [x] Add accessible labels for key values, including the stale status symbol (spec §6.5).
- [x] Verify with VoiceOver that the menu bar item and every popover value are read, and that a stale price is announced as not current (spec §12, criterion 7).
- [x] Check that the label stays readable with a larger menu bar text size and on a scaled display (spec §6.5).
- [x] Verify that frequent price updates do not cause visible flicker or excessive view work.

**Exit criteria:** The app provides the complete v1 experience without a separate main window.

### Milestone 4 — Minimal preferences and lifecycle

**Estimate:** 0.5–1 day

- [x] Add a launch-at-login toggle in the popover using `SMAppService.mainApp`. It reads `SMAppService.mainApp.status` (not `UserDefaults`) every time the popover opens and explains `.requiresApproval`; on a `register()`/`unregister()` error or `.notFound`, it reverts to the system status and shows a short message (spec §6.3). First verify which signal fires on every popover open; `onAppear` may fire only once. Record it in the verification log (§9). Use the same signal to re-evaluate the last-update date prefix (spec §6.4), and verify it: with stale data from before midnight, open the popover after midnight and see the date. A debug build registers its DerivedData path: turn the toggle off before deleting that build, and before M5 tests from `/Applications`, so no stale login item is left behind.
- [x] Add a toggle in the popover to show or hide the 24-hour percentage in the menu bar (default: shown), stored with `@AppStorage`.
- [x] Verify both toggles show the right value after an app restart.
- [x] Verify app launch, quit, and relaunch behavior (sleep/wake is tested in M5).
- [x] Verify that opening a second copy (a copy of the app in another folder while the first runs; the DMG only exists from M5) quits it, leaving one menu bar item and one connection, with no second item shown even briefly. Record the result in the verification log (§9).

**Exit criteria:** The two v1 preferences work reliably from the popover, with no separate Settings window, and remain intentionally limited.

### Milestone 5 — Quality, packaging, and release

**Estimate:** 1–2 days of work, plus at least 25 hours of elapsed time for the continuous run (longer if the connection drops during it)

- [x] Run the full automated test suite.
- [x] Test with network unavailable at startup.
- [x] Test network loss and recovery.
- [x] Test sleep and wake.
- [x] **Replaced by maintainer decision (2026-11-07)** with a 5-minute run against a local server that closes every connection after 60 s (§9); the 24-hour run was not done. Original item: Run a release build continuously against Binance until one connection has stayed open for 24 hours and Binance has closed it, with the Mac on AC power and kept awake (`caffeinate -dims`; `-s` only works on AC power). That takes at least 25 hours: any reconnect during the run (a Wi-Fi drop, the watchdog) restarts the 24-hour count, so extend the run past the last reconnect. Capture the log for the whole run with `mkdir -p build && log stream --predicate 'subsystem == "io.github.allisson.BitcoinTicker"' > build/run.log` (`build/` is ignored by Git), and check that the app reconnected after the close and that the price stayed Live through it (spec §12, criterion 9). A Stale period elsewhere in the run (a Wi-Fi drop, for example) does not fail the check if it matches a logged connection loss.
- [x] Confirm with Instruments (Time Profiler) that between ticker messages the app does no work besides the store's deadline task and the client's pending sleeps, with no polling (spec §12), and record CPU and memory usage in the release notes.
- [x] Verify no credentials, analytics, or unnecessary permissions are present.
- [x] Build a Universal (arm64 + x86_64) release with `xcodebuild archive -scheme BitcoinTicker -configuration Release -archivePath build/BitcoinTicker.xcarchive ONLY_ACTIVE_ARCH=NO`, and copy the `.app` out of the archive's `Products/Applications/` (the command line keeps the step scriptable; Organizer's Custom → Copy App is equivalent). Confirm both architectures with `lipo -archs "Bitcoin Ticker.app/Contents/MacOS/Bitcoin Ticker"` (`lipo` reads the binary, not the bundle). `lipo` only shows the slice is there: quit any running arm64 copy first (the single-instance check, spec §7, would quit the Rosetta launch silently), then launch it once with `arch -x86_64 "Bitcoin Ticker.app/Contents/MacOS/Bitcoin Ticker"` under Rosetta (or on an Intel Mac with macOS 14 to 26), confirm it shows the price, and record the result in the verification log (§9). Xcode 27 and macOS 27 run only on Apple silicon, so nothing else exercises the Intel slice (spec §11).
- [x] Confirm the release `.app` is ad hoc signed, with hardened runtime and App Sandbox (`codesign -dv --entitlements - "Bitcoin Ticker.app"`): flags `adhoc,runtime`, and only `com.apple.security.app-sandbox` and `com.apple.security.network.client`. Check the `.app` from the archive: a plain `xcodebuild build` of Release also carries `com.apple.security.get-task-allow`, and Debug builds have no hardened runtime (Xcode 27 turns it off there).
- [x] Create a DMG containing only the app and a link to `/Applications` for drag-install (`ln -s /Applications <dir>/Applications`, then `hdiutil create -volname "Bitcoin Ticker" -srcfolder <dir> -format UDZO BitcoinTicker-<version>.dmg`). Write concise installation, manual update, and uninstall instructions in the README and the release notes (uninstall: turn off Launch at login first, then delete the app and its sandbox container; verify that the container can be deleted that way, record the result in the verification log (§9), and document the steps that actually work; spec §11). Installation starts with dragging the app to `/Applications`, then covers the Gatekeeper steps for macOS 14 and macOS 15 or later (spec §11).
- [ ] Publish the DMG as a GitHub pre-release (tag and DMG name with the `-rc.<CURRENT_PROJECT_VERSION>` suffix, spec §11), with its SHA-256 checksum in the notes, download it, check the checksum on a Mac that never built the app, and follow the installation instructions on the current macOS release (macOS 27), macOS 15, and macOS 14 (a macOS 14 virtual machine is enough). If macOS 14 cannot be tested, mark its Gatekeeper steps as unverified in the instructions.
- [ ] On macOS 14, after installing, repeat the checks done only on the development Mac: the `MenuBarExtra` label (M0), the light/dark layout (M3), and the signal that fires on every popover open (M4). Record the result in the verification log (§9); if any differs, fix it before the release.
- [x] Publish a second build (`CURRENT_PROJECT_VERSION` incremented, spec §11) as another pre-release, with its own `-rc.<CURRENT_PROJECT_VERSION>` tag and checksum, and download it, so it is quarantined like a real update: a locally built copy is not, and Gatekeeper would never ask again. Install it over the first, and record whether Gatekeeper asks again, whether launch at login survives, and whether macOS prompts for access to the sandbox container or the "Show 24h change" preference is lost (spec §11). Record the result in the verification log (§9) and document it in the update instructions.
- [ ] Carry the DMG's SHA-256 checksum into the release notes of the final release.
- [ ] Promote the last pre-release to the first GitHub Release: tag `v1.0.0` on its commit and publish its same DMG renamed `BitcoinTicker-1.0.0.dmg` (spec §11); the checksum does not change. Any code change after a pre-release (for example, a fix from the macOS 14 check above) needs a new pre-release and a repeat of the update check above; a change to the networking or state code also repeats the continuous run and the Instruments check.
- [ ] Document known limitations (including regional availability) and troubleshooting, including a menu bar item hidden by the notch or by the system's menu bar settings (spec §6.1, §11). Verify on the current release (macOS 27; the setting appeared in macOS 26) which setting hides third-party items, record it in the verification log (§9), and name it in the instructions.
- [ ] State in the README and the release notes that the app displays exchange-provided market data and is not a trading or investment service (spec §10).

**Exit criteria:** A user can download, verify, install, launch, and use the app without Xcode, following only the published Gatekeeper instructions.

## 4. Implementation order

Follow the milestone order. Keep the application buildable after every step, and add tests in the same step as the code:

1. Menu bar shell with Quit (M0).
2. Binance message model and parser (M1).
3. Transport protocol, WebSocket connection, and receive loop (M1).
4. Client reconnection, delays, and lifecycle (M2a).
5. Observable market data state, freshness, watchdog, path, and wake (M2b).
6. Price in the menu bar, then popover details (M3).
7. Two preference toggles in the popover (M4).
8. Release packaging (M5).

Do not build charts, alerts, multiple-symbol support, or additional exchange abstractions during this roadmap.

## 5. Definition of done

### Functional

- [ ] All acceptance criteria in spec §12 are met.

### Engineering

- [ ] Networking and parsing are independent of SwiftUI views.
- [ ] Mutable state has a clear Swift concurrency isolation strategy.
- [ ] Only one WebSocket connection/receive loop is active at a time.
- [ ] Reconnect and freshness behavior are bounded and tested with an injected clock.
- [ ] Malformed exchange messages cannot crash the app.
- [ ] Price and percentage formatting is centralized.
- [ ] Core logic has automated test coverage.
- [ ] CI passes on `main`.
- [ ] No unnecessary third-party dependencies are introduced.

### Release

- [ ] Version, build number, Git tag, and DMG name follow spec §11.
- [ ] Every row of the verification log (§9) has a result.
- [ ] Universal release artifact is generated.
- [ ] App is ad hoc signed with hardened runtime and App Sandbox.
- [ ] GitHub Release contains the DMG, its SHA-256 checksum, and installation instructions with the Gatekeeper steps.
- [ ] README explains the data source, regional availability, limitations, how to build from source, and that the app is not a trading or investment service.

## 6. Risks and implementation notes

The reconnect, freshness, and parsing risks (half-open connections, flapping network paths, rejections and IP bans, the 24-hour close, malformed payloads, decimal precision, duplicate connections, a stale price shown as live) are handled by spec rules §5.3 to §5.6 and covered by the tests of M1, M2a, and M2b. They are not repeated here.

| Risk | Mitigation |
|---|---|
| Binance disconnects clients that do not answer pings within one minute | Verify automatic pong in M1; if missing, switch the transport to `NWConnection`, since `URLSessionWebSocketTask` cannot send a pong |
| Port 9443 blocked by corporate or public networks | Connect on port 443 |
| 451 cannot be produced from a developer machine outside a blocked region | Verify status readability against a local test server or a VPN in M1 |
| Binance rejects connections from the user's region | Unavailable state, fixed delay, and a documented limitation in the README and the release notes |
| `MenuBarExtra` label ignores `.monospacedDigit()` or the composite label | Verify in M0; fall back to a template image rendered with `ImageRenderer` |
| `MenuBarExtra` limitations (template label without color or reliable dimming, no Dock icon to quit) | Sign and status symbol instead of color or opacity; preferences and Quit in the popover |
| Menu bar item hidden (notch, or the system's menu bar settings): no Dock icon, and a second launch quits silently, so the app runs unreachable | Troubleshooting instructions: free space, allow the item, quit from Activity Monitor (spec §11) |
| Two copies of the app run at once (DMG and `/Applications`) | Single-instance check at launch (spec §7); verified in M4 |
| Non-notarized app: Gatekeeper blocks the first launch, and users may distrust the download | Step-by-step Gatekeeper instructions for macOS 14 and 15+, published SHA-256 checksum, Developer ID in the post-v1 backlog |
| Each update has a new ad hoc signature | Verify in M5 whether Gatekeeper approval, launch at login, and access to the sandbox container (stored preference) survive an update; document the steps |
| The Intel slice is never exercised on the build Mac | Launch it once under Rosetta in M5 |

## 7. Post-v1 backlog (not part of this release)

Consider these only after v1 is shipped and stable:

- Multiple Binance Spot symbols.
- User-selectable trading pairs.
- Other exchanges.
- Price alerts and native notifications.
- Intraday charts using a separate Binance kline stream.
- Additional menu bar display formats.
- More detailed refresh and display preferences, including price precision.
- Automatic updates.
- Developer ID signing and notarization (requires an Apple Developer Program membership).

## 8. Handoff instructions for the coding agent

Use `spec.md` as the source of truth for product behavior and technical constraints. Use this `roadmap.md` to sequence implementation.

Before coding:

1. Inspect the repository and existing project structure.
2. Check the current official Binance WebSocket documentation for endpoint, payload, connection-lifetime, ping/pong, and rate-limit requirements.
3. Confirm the current macOS API details for `MenuBarExtra` (template label rendering, toggles inside a `.window` popover) and `SMAppService` (status values, `.requiresApproval`).
4. Present a concise implementation plan and identify any conflicts between the repository, this roadmap, and the specification.
5. Ask for clarification only when a decision materially affects architecture or user-visible behavior.

During implementation:

- Keep the project buildable after each milestone.
- Prefer native APIs and minimal dependencies.
- Do not expand scope beyond v1 without approval.
- Add tests alongside the relevant implementation.
- Do not claim a feature is complete unless it is implemented and verified.
- Update this roadmap's checkboxes as milestones are completed.
- Fill in the verification log (§9) as each manual verification is done.

## 9. Verification log

Results of the one-off manual verifications. A known limitation recorded here counts for spec §12 once it is also stated in the README and the release notes.

| Milestone | Verification | Result | Date |
|---|---|---|---|
| M0 | `MenuBarExtra` label renders the composite label and honors `.monospacedDigit()`; `ImageRenderer` fallback needed? (spec §6.1) | Renders the SF Symbol, price, and percentage; same width for `11,111.11` and `88,888.88`, so `.monospacedDigit()` is honored. No fallback needed. Checked on macOS 26.6.2 with Xcode 27.2, through the Debug-only `-MenuBarLabelPreview` argument | 2026-11-06 |
| M0 | Signal that detects the unit-test host, under both test plan configurations; the suite runs to the end with no second menu bar item (spec §7) | `XCTestConfigurationFilePath` is set in both configurations (Default and Brazil). With the Debug app launched outside Xcode, `xcodebuild test` ran to the end, showed no second menu bar item, and left the running app alive | 2026-11-06 |
| M1, M2b | Test suite opens no WebSocket connection while a Debug build runs (M1 with the client, repeated in M2b with the store; spec §7) | M1: with the Debug app connected to Binance, `xcodebuild test` passed in both configurations and the app stayed alive. The test process logged only the 8 `Connecting` changes per configuration of the 8 fake-transport tests that call `start()`, none from a client started by the app. M2b: with the Debug app connected to Binance, `xcodebuild test` passed in both configurations (68 tests) and the app stayed alive. The test processes logged no `com.apple.network` or `com.apple.CFNetwork` message (the app process logged 235 in the same window), so no store or URLSession transport ran in the test host | 2026-11-06 |
| M1 | HTTP status of a rejected upgrade readable from the task's `response` (spec §5.2) | Readable on `URLSessionWebSocketTask`: a local server on `ws://127.0.0.1` rejecting the upgrade gave status 451 (Unavailable) and 429 (Rate limited) | 2026-11-06 |
| M1 | `Retry-After` readable from the task's `response` (spec §5.2) | Readable: the 429 rejection carried `Retry-After: 120` and the client read `120` | 2026-11-06 |
| M1 | Automatic pong: transport kept (`URLSessionWebSocketTask` or `NWConnection`) (spec §5.5) | `URLSessionWebSocketTask` kept: one connection to `stream.binance.com` stayed open 6 min 19 s with 372 ticker messages and no close, so pongs are sent | 2026-11-06 |
| M1 | Endpoint kept (`stream.binance.com` or `data-stream.binance.vision`) (spec §5.2) | `stream.binance.com` kept: it passed the handshake, payload, and ping/pong checks | 2026-11-06 |
| M3 | Layout in light and dark appearances on macOS 27, including the translucent menu bar (spec §6.5) | macOS 27: pending. On macOS 26.6.2 (translucent menu bar): label and popover read correctly in light and dark, in Live, Stale, No data, Unavailable, and Rate limited; the long statuses wrap instead of truncating. Label also readable with Menu bar size Large and on a scaled resolution | 2026-11-06 |
| M3 | VoiceOver reads the menu bar item and every popover value; a stale price is announced as not current (spec §6.5, §12) | Passed on macOS 26.6.2: the item reads "Bitcoin price 67.431,07, 24-hour change +2,45%", and "Bitcoin price not current: …" when stale; every popover value is read, and the stale price as "Price not current: …" | 2026-11-06 |
| M4 | Signal that fires on every popover open (spec §6.3, §6.4) | The popover content's `onAppear` fired on every open (4 of 4, the first included) on macOS 26.6.2 with Xcode 27.2; `NSWindow.didBecomeKeyNotification` missed the first open. `onAppear` re-reads the launch-at-login status and the date used for the last-update prefix | 2026-11-06 |
| M4 | `SMAppService.mainApp.status` of a Debug build never registered (spec §6.3) | `.notFound`; `register()` then succeeded (`.enabled`), and after `unregister()` the status was `.notRegistered`. So `.notFound` explains itself only after a register or unregister attempt (spec §6.3) | 2026-11-06 |
| M4 | A second copy quits at launch: one menu bar item, one connection, no second item shown even briefly (spec §7) | Passed on macOS 26.6.2: a copy of the Debug app in another folder, opened with `open -n` while the first ran, exited at launch without any app log. A 6 s screen recording of the menu bar showed a single `₿` item in every changed frame, and the first copy kept one TCP connection (`nettop`). Both toggles kept their values after a restart, and Quit from the popover followed by a relaunch reconnected (No data → Live) | 2026-11-06 |
| M4 | Last-update date prefix appears when the popover opens after midnight with stale data (spec §6.4) | Passed on macOS 26.6.2: with data stale since 22:46:02 on Nov 6 and the popover closed, opening it at 00:00:17 on Nov 7 showed "Last update: 6 Nov, 22:46:02". Launch at login was then turned off from the popover, and Login Items shows the Debug build disabled | 2026-11-07 |
| M5 | Network unavailable at startup, then loss and recovery while Live (spec §5.5, §5.6) | Passed with the archived Release app on macOS 26.6.2, Wi-Fi turned off with `networksetup`: launched with no network, it showed No internet connection with `—` everywhere, and reached Live 1.5 s after the path returned. Live, then Wi-Fi off: Offline at once, Stale 30 s after the last ticker with the warning in the menu bar and popover, and Reconnecting → Connected → Live within 2 s of the path returning | 2026-11-07 |
| M5 | Sleep and wake (spec §5.5, §5.6) | Passed with the archived Release app on macOS 26.6.2: asleep from 00:22:52 to 00:25:04 (`pmset -g log`). On wake the freshness deadline had passed (`ContinuousClock` counts sleep): Live → Stale and a watchdog reconnect at 00:25:04.000, the wake notification at 00:25:04.377 added no second attempt, Connected at 00:25:05.860 and Live at 00:25:06.045 | 2026-11-07 |
| M5 | Sandbox container can be deleted as the uninstall instructions say (spec §11) | Passed on macOS 26.6.2: the maintainer followed the README uninstall steps for `v1.0.0-rc.2` (Launch at login off, Quit, delete the app, `rm -rf ~/Library/Containers/io.github.allisson.BitcoinTicker`) with no block reported; afterwards the app and the container were gone and Login Items kept only a disabled record of `/Applications/Bitcoin Ticker.app` | 2026-11-07 |
| M5 | After an update: Gatekeeper asks again? launch at login survives? container prompt or lost preference? (spec §11) | On macOS 26.6.2, `v1.0.0-rc.2` (build 2) downloaded with Chrome and dragged in Finder over `v1.0.0-rc.1` in Applications: Gatekeeper asked again ("Not Opened", then Open Anyway). Launch at login survived (Login Items: enabled, same `/Applications` URL, generation 1, toggle on). No prompt to access the container, and the stored "Show 24h change" value was kept (the preference file was not rewritten by the update). The Finder copy ran from Applications, not translocated | 2026-11-07 |
| M5 | Intel (x86_64) slice launches and shows the price, under Rosetta or on an Intel Mac (spec §11) | Passed under Rosetta on macOS 26.6.2: the archived Release app (`lipo`: `x86_64 arm64`), launched with `arch -x86_64`, ran as "X86-64 (translated)" (`vmmap`), reached Live, and its popover showed the price | 2026-11-07 |
| M5 | macOS 27 setting that hides third-party menu bar items (spec §6.1, §11) | — | — |
| M5 | Gatekeeper steps tested on the current macOS, macOS 15, and macOS 14 (spec §11) | macOS 26.6.2: passed. The `v1.0.0-rc.1` DMG downloaded with Chrome matched its published SHA-256 and was quarantined; opening the app from Applications showed "“Bitcoin Ticker.app” Not Opened" (Move to Trash, Done); after Done, Privacy & Security → Open Anyway asked for the password or Touch ID, and the app reached Live. The app was copied to Applications with `ditto` instead of a Finder drag, so it ran translocated; Launch at login still registered `/Applications/Bitcoin Ticker.app` (Login Items: enabled). macOS 15 and macOS 14: pending | 2026-11-07 |
| M5 | macOS 14: label, layout, and popover-open signal match the development Mac (spec §6.1, §6.3) | — | — |
| M5 | Continuous run: a connection lasted 24 hours, Binance closed it, the app reconnected, and the price stayed Live through it; run length (spec §5.5, §5.6) | Not run, by maintainer decision: 25 hours was judged too long. Replaced by a Debug build against a local server that sent one ticker per second and closed every connection with a 1000 close frame after 60 s, for 5 minutes on macOS 26.6.2: five closes, each logged as "Connection closed after it was stable", then Reconnecting → Connected within 0.3–0.95 s (backoff k = 1), and the freshness stayed Live the whole run (no Stale transition). The client closed each connection before opening the next (the server briefly counted 2 once, because its handler waits 0.5 s after sending the close frame) | 2026-11-07 |
| M5 | Instruments: no work between ticker messages besides the deadline task and pending sleeps; CPU and memory recorded (spec §12) | Passed: Time Profiler attached for 60 s to the archived Release app (arm64, Live against Binance) took 541 samples of 1 ms, about 0.9% CPU; every sample with an app frame was on the ticker path (receive, parse, store, formatter, view), and the run-loop timers sampled were AppKit's own, none from the app. Memory footprint 14 MB (`footprint`). Checked on macOS 26.6.2 | 2026-11-07 |
