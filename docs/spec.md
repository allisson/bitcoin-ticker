# Bitcoin Ticker for macOS — Product & Technical Specification

**Document status:** Reviewed, ready for implementation  
**Target release:** v1.0  
**Working name:** Bitcoin Ticker  
**Platform:** macOS 14 (Sonoma) or later  
**Primary market:** Binance Spot `BTCUSDT`

## 1. Overview

Bitcoin Ticker is a small, native macOS menu bar application that displays the live Bitcoin price for the Binance Spot `BTCUSDT` market.

The application is intentionally narrow in scope. It is not a trading terminal, portfolio tracker, wallet, or exchange client. Its primary job is to make the current BTC/USDT price immediately visible without requiring the user to open a browser or a full desktop application.

The application must retrieve public market data directly from Binance. It must not require a Binance account, API key, or application-owned backend.

## 2. Product goals

### 2.1 Goals

- Display the latest `BTCUSDT` price from Binance Spot in the macOS menu bar.
- Receive market updates through Binance's public WebSocket API.
- Show the 24-hour percentage change alongside the price by default; the user can hide it (§6.3).
- Provide a compact popover with additional 24-hour market information.
- Recover gracefully from network interruptions and WebSocket disconnections.
- Keep resource usage low and avoid unnecessary background work.
- Ship as a native macOS application that can be distributed independently of the Mac App Store.

### 2.2 Non-goals for v1

- Trading, order placement, account access, or portfolio management.
- Binance API-key support or authenticated endpoints.
- Multiple exchanges or trading pairs.
- Price alerts and macOS notifications.
- Charts of any kind, widgets, or technical indicators.
- User accounts, cloud synchronization, telemetry, or an application backend.
- Automatic in-app updates. Users update manually from GitHub Releases.

## 3. Target users and primary workflow

The target user wants to glance at the current BTC/USDT price while working on macOS.

Primary workflow:

1. The user launches Bitcoin Ticker.
2. The app connects to Binance's public WebSocket endpoint.
3. The menu bar displays the latest available BTC/USDT price.
4. The user clicks the menu bar item to inspect the 24-hour change, high, low, and volume.
5. If connectivity is lost, the app indicates that the displayed data is stale or unavailable and reconnects automatically.

## 4. Platform and technology

Use native Apple technologies and avoid third-party dependencies unless there is a clear technical justification.

| Area | Choice |
|---|---|
| Language | Swift, Swift 6 language mode (complete concurrency checking) |
| Default actor isolation | `nonisolated` (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Xcode 26 app templates default to `MainActor` (check the template of the Xcode version in use), which would pin the parser, the formatter, and the client's protocols to the main actor (§7) |
| Approachable Concurrency | `YES` (`SWIFT_APPROACHABLE_CONCURRENCY`, the Xcode 26 template default), set explicitly. It turns on `NonisolatedNonsendingByDefault`: a `nonisolated` `async` function runs on its caller's actor. Mark a function `@concurrent` only if it must leave the caller's actor; in this design the networking work already lives in the client actor (§7) |
| Toolchain | Xcode 26 (Swift 6.2) or later; Xcode 27 runs only on Apple silicon (§11). The two build settings above do not exist before Xcode 26 |
| Tests | Swift Testing |
| UI | SwiftUI |
| Menu bar integration | SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` |
| App presence | Menu bar only, no Dock icon (`LSUIElement` = `YES`, set through the `INFOPLIST_KEY_LSUIElement` build setting; the Xcode template generates the Info.plist) |
| Product name | `Bitcoin Ticker` (`PRODUCT_NAME`, with the space), so the bundle is `Bitcoin Ticker.app` (§11). Module name `BitcoinTicker` (`PRODUCT_MODULE_NAME`), so tests use `@testable import BitcoinTicker` |
| Bundle identifier | `io.github.allisson.BitcoinTicker` (Release; Debug adds a `.debug` suffix). Fixed from v1 on: the sandbox container path, the stored preference, and the launch-at-login registration depend on it, and changing it loses them |
| Networking | `URLSessionWebSocketTask` |
| Network reachability | `NWPathMonitor` |
| Sleep/wake | `NSWorkspace.didWakeNotification`, observed on `NSWorkspace.shared.notificationCenter` (it is never posted to `NotificationCenter.default`) |
| Concurrency | Swift Concurrency (`async`/`await`, actors where appropriate) |
| Observable state | Observation framework (`@Observable`) |
| Charts | None in v1 |
| Preferences | `UserDefaults` / `@AppStorage` |
| Launch at login | `SMAppService.mainApp` |
| Minimum OS | macOS 14 |
| Build | Xcode application project, no Swift package (see below) |
| Distribution | DMG containing an ad hoc signed, non-notarized Universal app, published on GitHub Releases (§11) |

Prefer a simple Xcode application project. Do not introduce a package or framework solely to wrap functionality already provided by the operating system.

## 5. Binance market data integration

### 5.1 Market

- Exchange: Binance Spot
- Symbol: `BTCUSDT`
- Stream: `btcusdt@ticker`
- Data type: public 24-hour rolling ticker statistics
- Update speed: 1000 ms (per Binance documentation)

### 5.2 WebSocket endpoint

Use Binance's documented Spot WebSocket endpoint:

```text
wss://stream.binance.com:443/ws/btcusdt@ticker
```

Binance documents both port 443 and port 9443 for this host. Use 443: corporate and public networks often block 9443.

The endpoint and stream format must be isolated behind the Binance client so they can be changed without affecting the UI or market-data state model.

Binance also documents `wss://data-stream.binance.vision`, a market-data-only endpoint. v1 uses `stream.binance.com`. The choice of endpoint is a build-time decision, made once during Milestone 1: switch the constant to `data-stream.binance.vision` only if `stream.binance.com` fails any of the Milestone 1 checks (handshake, payload, ping/pong) and the alternative passes all of them. A test from one developer machine says nothing about regional blocking, so this decision does not address it. The app never switches endpoints at runtime.

**Regional availability:** Binance rejects connections from some jurisdictions (for example, the United States). Binance's documentation does not list 451; it comes from developer reports of geo-blocked IPs. The documented codes are REST codes: 403 is a WAF (Web Application Firewall) block, either a rate-limit violation or a security block; 429 is a broken rate limit; 418 is an automatic IP ban after ignoring 429s, lasting from 2 minutes to 3 days for repeat offenders, and both 429 and 418 carry `Retry-After` in seconds. Whether the WebSocket upgrade returns the same codes is not documented. Map the HTTP status of a rejected WebSocket upgrade as follows:

| HTTP status | Meaning | Connection state |
|---|---|---|
| 451, 403 | Regional restriction (451) or WAF block of this network (403) | *Unavailable* (§5.7), next attempt after the fixed delay (§5.5) |
| 429, 418 | Rate limit or IP ban | *Rate limited* (§5.7), next attempt after the fixed delay (§5.5) |
| Any other status | Unexpected rejection | *Connecting* before the first completed handshake, *Reconnecting* after (§5.7); normal backoff |
| Status not readable | Unknown failure | *Connecting* before the first completed handshake, *Reconnecting* after (§5.7); normal backoff |

A rejection with 451, 403, 429, or 418 is never retried before the fixed delay ends. Verify during Milestone 1 that the HTTP status of a failed upgrade is readable from the task's `response` (`HTTPURLResponse.statusCode`), and that its `Retry-After` header is readable too. If the status is not readable, every rejection falls into the last row, and the Unavailable state cannot be detected: record this as a known limitation (§12). If only `Retry-After` is unreadable, the fixed delay is always 60 s: record that as well.

Official documentation:
- WebSocket streams: https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams
- General Spot API documentation: https://developers.binance.com/docs/binance-spot-api-docs

### 5.3 Required ticker fields

Parse only the fields needed by v1:

| JSON field | Meaning | App usage |
|---|---|---|
| `s` | Symbol | Validate that the message is for `BTCUSDT` |
| `c` | Last price | Main displayed price |
| `P` | Price change percent over 24 hours | Menu bar and popover |
| `h` | 24-hour high | Popover |
| `l` | 24-hour low | Popover |
| `v` | 24-hour base-asset volume | Popover |

Ignore every other field, including `E` (event time): it is not used for freshness (§5.6).

Treat numeric values received as JSON strings as decimal values. Parse them with `Decimal(string:locale:)` and `locale: nil`, so the period is always the decimal separator, not through `Double`. Use `Decimal` for price and percentage parsing and formatting. Parsing tests must also pass when the process locale uses a comma as the decimal separator (for example, `pt_BR`). Swift Testing cannot change `Locale.current` inside the test process, so run this check through a test plan configuration with the language set to Portuguese (Brazil) and the region set to Brazil. The region alone may not give a comma separator (with an English language the locale becomes `en_BR`), so the test first asserts `Locale.current.decimalSeparator == ","`; otherwise it could pass without exercising the comma. The test plan runs the whole suite in both configurations, and that assertion fails in the default one: the Brazil configuration sets an environment variable (`EXPECT_COMMA_DECIMAL=1`), and the comma-locale test runs only when it is set (`.enabled(if:)`).

Reject a value unless the whole string is a plain decimal number: an optional `-`, digits, and an optional `.` followed by digits. Check it with a whole-string match (`value.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/)`), not with `^…$` anchors: in ICU (`NSRegularExpression`), `$` also matches before a trailing newline, so `"12\n"` would pass. Check this before calling `Decimal(string:locale:)`, which accepts a valid prefix (for example, `"12abc"` → `12`). Cover both cases with tests. Also reject any value longer than 32 characters: `Decimal` keeps at most 38 significant digits, and `Decimal(string:locale:)` silently approximates a longer digit string instead of returning `nil`. Binance values are far shorter. If `Decimal(string:locale:)` still returns `nil`, reject the message too.

Only text frames carry ticker messages. Treat a binary frame as a malformed message.

Reject the whole message unless `c`, `h`, and `l` are greater than zero and `v` is zero or greater. `P` may be negative. The pattern above already rejects `NaN` and infinity, so no separate finiteness check is needed.

`P` is already expressed in percentage points (`"2.45"` means +2.45%). The formatter must not multiply it by 100. Cover this with a test.

### 5.4 Data semantics

The `@ticker` stream represents rolling 24-hour ticker statistics. It is not a candle stream and does not provide a fixed UTC-day open/close.

The UI must label the data as **24h** rather than implying that it represents the current calendar day.

The displayed last price is the latest price reported by Binance for the selected Spot market. It is not an average across exchanges.

### 5.5 Connection lifecycle

Binance's documented connection rules:

- A single connection to `stream.binance.com` is valid for 24 hours.
- The server sends a ping frame every 20 seconds and disconnects if it receives no pong within one minute. The pong must echo the ping's payload. Unsolicited pongs are allowed but do not prevent the disconnection.
- A connection may send at most 5 messages per second; ping frames, pong frames, and JSON control messages all count. A connection over the limit is disconnected, and an IP disconnected repeatedly may be banned. The app sends only pongs, so it stays far below this; an explicit pong implementation (below) must never send more.
- An IP may open at most 300 connections every 5 minutes.

The Binance client must:

- Connect automatically when the app starts.
- Consume messages continuously while the app is active.
- Answer server pings with pongs. Verify during Milestone 1 that `URLSessionWebSocketTask` does this automatically. Its API cannot do it explicitly: it neither exposes received ping frames nor sends pong frames (only `sendPing`). If the automatic pong is missing, replace the transport implementation with `NWConnection` and `NWProtocolWebSocket.Options` (`autoReplyPing`, or `autoReplyPing = false` and an explicit pong echoing the payload). The transport protocol (§7) keeps this change out of the client; repeat the Milestone 1 checks of the rejected-upgrade status and `Retry-After` (§5.2) on the new transport.
- Handle WebSocket completion and errors.
- Discard a malformed message (invalid JSON, a binary frame, a missing or invalid field, an unexpected symbol; §5.3) and keep the connection open. It emits no ticker event, so if only malformed messages arrive the data turns Stale (§5.6) and the watchdog reconnects. Log only the first malformed message of each connection, at `.error`: a changed payload format would otherwise log once per second.
- Reconnect after unexpected disconnection.
- Fail a handshake that has not completed within the handshake timeout (default: 10 s), and treat it like any other failed attempt. Without it, a hung handshake would leave the app in Connecting or Reconnecting, where the watchdog (§5.6) does nothing.
- Use exponential backoff with full jitter: base delay 1 s, doubling per failed attempt, capped at 60 s. *k* is the index of the next backoff retry: it starts at 1, goes back to 1 when a connection becomes stable (below) and when a fixed delay starts, and grows by 1 after each failed attempt (including a connection that closes before it is stable), except the attempt that ends a fixed delay, which leaves it at 1. The delay before the *k*-th retry is a random value between 0 and `min(60 s, 1 s × 2^(k−1))`: up to 1 s, then 2 s, 4 s, and so on up to 60 s.
- After a rejection with 451, 403, 429, or 418 (§5.2), wait a **fixed delay** instead: exactly 60 s, without jitter, or the `Retry-After` header value when present and longer. Read `Retry-After` only as a whole number of seconds (digits only); any other form (for example, an HTTP date) is ignored and the delay is 60 s. Cap the delay at 3 days, the longest ban Binance documents (§5.2): the header comes from the network, and an unbounded value could suspend the app indefinitely. A digits-only value too large for an integer is over the cap, not malformed: the delay is 3 days.
- Report Connected only once the handshake has completed. `receive()` alone does not report a completed handshake: the transport learns of it from `URLSessionWebSocketDelegate.urlSession(_:webSocketTask:didOpenWithProtocol:)`, and of a failed one from `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`. The transport protocol exposes both, and the handshake timeout relies on them. Every change to Connected marks a new handshake; the watchdog (§5.6) measures from it.
- Reset the retry delay (k back to 1) once a connection is stable: it has delivered at least one valid ticker message and has stayed open for the stability interval (default: 30 s). Check this on each valid message, so no extra timer is needed. A connection that closes before it is stable counts as a failed attempt and increments k, unless `reconnect()` closed it (below). Otherwise a server that accepts the handshake, sends one message, and closes would drive a reconnect as often as the minimum attempt interval (below) allows: every 2 s, 150 connections every 5 minutes, indefinitely, half of Binance's per-IP limit.
- Allow only one connection and one receive loop at any time. Close the old connection before opening a new one. Discard any message a connection delivers after it was closed or replaced: ticker events come only from the current, open connection, so the first valid event after any gap always follows the change to Connected (§5.6 relies on this).
- Never start two connection attempts less than the minimum attempt interval apart (default: 2 s), measured between attempt starts, whatever triggered them: backoff, `reconnect()`, or `setNetworkAvailable(true)`. An attempt due earlier waits for the rest of the interval; "immediately" elsewhere in this section means "as soon as this interval allows". A `reconnect()` or `setNetworkAvailable(true)` that arrives while an attempt is already waiting for this interval does nothing more: that waiting attempt is the one that runs. This one rule bounds the client at 150 connections every 5 minutes, half of Binance's limit, even when the network path flaps or wake and path events repeat.
- Treat Binance's close at the end of the 24-hour connection lifetime like any other drop; there is no proactive rotation. That connection was stable, so k is back at 1 and the new attempt starts after the k = 1 backoff delay (at most 1 s, and never before the minimum attempt interval allows). The price stays Live through the gap (§5.6); the popover shows "Reconnecting…" only during that short backoff wait and the new handshake.
- Expose a `reconnect()` operation: close the current connection, if any, and start a new attempt immediately, skipping any pending backoff delay but never a pending fixed delay. `MarketDataStore` calls it from the watchdog (§5.6), because a half-open TCP connection may never complete `receive()`, and after `NSWorkspace.didWakeNotification`. While Offline, `reconnect()` does nothing. While a handshake is in progress, `reconnect()` also does nothing, so wake and a path change arriving together do not abort the attempt the first one started. A `reconnect()` is not a failed attempt and does not increment k, even when it closes a connection that was not yet stable. Consequence: a server that accepts the handshake and never sends data gets one watchdog reconnect per freshness threshold (§5.6), with no backoff: at the 30 s default, at most 10 connections every 5 minutes, far below Binance's limit of 300.
- Expose a `setNetworkAvailable(_:)` operation. With `false`, close the connection, suspend all attempts, and report Offline. Like `reconnect()`, closing a connection this way is not a failed attempt and does not increment k; the minimum attempt interval (above) bounds how often a flapping path can reconnect. Leaving Offline does not change k either. With `true`, leave Offline first, then behave like `reconnect()` (which does nothing while Offline). The state reported on leaving Offline is the state the last fixed delay set (Unavailable after 451/403, Rate limited after 429/418), if that delay is still pending or the attempt that follows it has not run yet (§5.7); otherwise Connecting if no handshake has completed since launch; otherwise Reconnecting. The fixed delay comes first: after a 451 on the very first attempt, the state on leaving Offline is Unavailable, not Connecting, whether the delay ended during Offline or is still pending. The network is available unless the path status is `.unsatisfied`: `.requiresConnection` counts as available, because only a connection attempt can activate such a path (for example, an on-demand VPN), and treating it as Offline would leave the app Offline forever. The store calls it only when this availability changes: `NWPathMonitor` also reports the initial path at startup and interface changes that keep the path satisfied (for example, Wi-Fi to Ethernet), and neither may tear down a connection. The initial report counts as a change only when it is unsatisfied.
- Cancel tasks and release resources when the app shuts down.

Summary of the retry rules above, one row per event. The bullets are authoritative; every attempt also waits for the minimum attempt interval.

| Event | k | Next attempt | Connection state (§5.7) |
|---|---|---|---|
| App starts | 1 | Immediately | Connecting |
| Handshake completes | Unchanged | — | Connected |
| Connection becomes stable (a valid message, open for the stability interval) | Back to 1 | — | Connected |
| Attempt fails: other status, unreadable status, handshake timeout, transport error | +1, except on the attempt that ends a fixed delay (stays 1) | After the backoff delay for k | Connecting before the first handshake since launch, Reconnecting after |
| Connection closes before it is stable, not closed by `reconnect()` or `setNetworkAvailable(false)` | +1, except when its attempt ended a fixed delay (stays 1) | After the backoff delay for k | Reconnecting |
| Connection closes after it is stable (including Binance's 24-hour close) | 1 (already reset) | After the k = 1 backoff delay (at most 1 s) | Reconnecting |
| Handshake rejected with 451 or 403 | Back to 1 | After the fixed delay | Unavailable |
| Handshake rejected with 429 or 418 | Back to 1 | After the fixed delay | Rate limited |
| `reconnect()` while Connected or waiting for backoff | Unchanged | Immediately | Connecting before the first handshake since launch, Reconnecting after |
| `reconnect()` during a handshake, a fixed delay, or Offline | Unchanged | No change | Unchanged |
| `setNetworkAvailable(false)` | Unchanged | None; a pending fixed delay keeps counting | Offline |
| `setNetworkAvailable(true)` | Unchanged | As `reconnect()`, never before a pending fixed delay ends | The state the fixed delay set, if it is pending or its following attempt has not run; otherwise Connecting before the first handshake since launch, Reconnecting after |

`MarketDataStore`, not the client, observes `NWPathMonitor` and `NSWorkspace.didWakeNotification` and calls these operations. Network-path changes and wake never shorten a fixed delay: while one is pending, they only mark the next attempt as due when the delay ends. This keeps a flapping network from hammering Binance during a rejection or an IP ban. A pending fixed delay keeps counting while Offline. When the path returns, before or after the delay ends but before the attempt that follows it has run, the state goes back to the one the delay set (Unavailable after 451/403, Rate limited after 429/418), and the next attempt still waits for the delay to end.

A fixed delay is not persisted: after a relaunch (including launch at login), the first attempt runs immediately. This is accepted: it adds at most one attempt per launch during a rejection or an IP ban.

The client receives as injected dependencies: the connection URL, the handshake timeout, the backoff parameters, the stability interval, the minimum attempt interval, the WebSocket transport, the clock, and the random source used for jitter. The store receives the same clock, a wall-clock `now` source (§5.6), and the network-path and wake sources behind small protocols. Tests can then drive reconnect, freshness, Offline, and wake without real network, real time, or randomness. Swift ships no controllable test clock; write a small manual one in the test target instead of adding a third-party package.

For manual tests, Debug builds may override the connection URL through a launch argument, read from `UserDefaults` (its argument domain; for example, `-BinanceURL ws://127.0.0.1:8080`). Release builds ignore it.

Do not reconnect in a tight loop. Do not repeatedly log the same failure at high frequency.

### 5.6 Freshness and stale data

The application must distinguish between the last known price and a currently updating price.

- Record the local receive time of the last successfully parsed ticker event as an instant of the injected monotonic clock (`ContinuousClock` in production, the manual test clock in tests; §5.5). Do not use Binance's `E` field for freshness, because the two clocks can differ. Do not use `SuspendingClock`: it stops while the Mac sleeps, so after a wake without network an hours-old price would still read as Live. `ContinuousClock` keeps counting through sleep. A clock instant cannot be shown as a time of day, so also record the wall-clock time (`Date`) of the same event, from the injected `now` source, only for the last-update display (§6.4).
- Define a freshness threshold in one place in the code (default: 30 seconds; the stream updates every 1 second).
- **Display freshness:** if no valid event has arrived within the threshold since the last one, the data is Stale. This rule alone decides Live versus Stale, whatever the connection state.
- **Connection watchdog:** while the connection is Connected, if no valid event arrives within the threshold measured from the later of the last valid event and the moment the connection state last became Connected (the handshake, §5.5), call `client.reconnect()`. Measuring from the handshake keeps a new connection from being torn down before its first message arrives, and still catches a connection that is half-open from the start. In Connecting, Reconnecting, Rate limited, Offline, or Unavailable, the watchdog does nothing: the rules in §5.5 decide when the next attempt happens, so stale data cannot bypass a fixed delay.
- Do not present stale data as live.
- Retain the last known value while disconnected. It stays Live until the threshold passes, which keeps a brief drop (including Binance's 24-hour close, §5.5) from turning the price Stale, and then turns Stale, with the indicator in the menu bar and in the popover.
- If no valid price has ever been received, display a clear loading or unavailable state instead of a fabricated value.
- **Timing:** no message arrives to trigger the change from Live to Stale, so the store must schedule it. Use one long-lived task that sleeps on the injected clock until the earliest pending deadline (last valid event + threshold for freshness; the watchdog deadline while Connected), re-evaluates when it wakes, and sleeps again until the current deadline. Do not start or cancel a task per message. A deadline can appear when none is pending: for example, a handshake after the data has already turned Stale, or the first handshake since launch, creates a watchdog deadline. So, with no pending deadline, the task waits for a signal from the store, not on the clock; the store sends it on every connection-state change. Use an `AsyncStream<Void>` with `.bufferingNewest(1)`: a signal sent while the task sleeps on the clock is kept, and repeated signals do not pile up. Valid events come only from the current connection (§5.5), so every other deadline change only moves a deadline later: a sleeping task wakes early, re-evaluates, and sleeps again.

The freshness threshold is a product heuristic, not a Binance guarantee. Keep it centralized so it can be adjusted.

### 5.7 State model

Connection state and data freshness are separate dimensions. A connection can be open while its data is stale.

**Connection state:**

| State | Meaning |
|---|---|
| Connecting | No handshake has completed since launch and no fixed delay is pending: the first attempt, and every retry after a failure other than 451, 403, 429, or 418, including the backoff wait before it. Also the first attempt after the network path returns, if the app started Offline |
| Connected | WebSocket handshake completed; socket open (its data may still be stale) |
| Reconnecting | At least one handshake has completed since launch, and the app is waiting for a delay or re-establishing after a drop (including Binance's 24-hour close), a watchdog reconnect, wake, or a rejection other than 451, 403, 429, or 418 (§5.2) |
| Rate limited | Handshake rejected with HTTP 429 or 418 (§5.2), whether or not a handshake has completed since launch; next attempt only after the fixed delay (§5.5). The state stays Rate limited during that attempt and changes only when a handshake succeeds (Connected) or fails for another reason: Unavailable with a new fixed delay after 451/403, or normal backoff from k = 1 otherwise, in Connecting or Reconnecting per the rows above |
| Offline | No network path (`NWPathMonitor` reports `.unsatisfied`; `.requiresConnection` is not Offline, §5.5); no connection attempts. Takes precedence over every other state. A pending fixed delay keeps counting (§5.5) |
| Unavailable | Handshake rejected with HTTP 451 or 403 (§5.2); next attempt only after the fixed delay (§5.5). The state stays Unavailable during that attempt and changes only when a handshake succeeds (Connected) or fails for another reason: Rate limited with a new fixed delay after 429/418, or normal backoff from k = 1 otherwise, in Connecting or Reconnecting per the rows above |

**Data freshness:**

| State | Meaning |
|---|---|
| No data | No valid ticker received since launch |
| Live | Last valid ticker received within the freshness threshold |
| Stale | Last valid ticker is older than the freshness threshold |

## 6. User interface

### 6.1 Menu bar item

The menu bar item is the primary interface.

Default presentation:

```text
₿ 67,432.18  +2.45%
```

The values above are illustrative only.

Requirements:

- Display the Bitcoin symbol or a compact BTC identifier.
- Display the latest BTC/USDT price.
- Display the 24-hour percentage change when available. It is shown by default and can be hidden with the popover toggle (§6.3).
- Distinguish positive, negative, and unchanged values with an explicit sign (`+`, `−`, or none). `MenuBarExtra` labels render as template images, so color is not available in the menu bar. Color may be used in the popover in addition to the sign.
- Keep the layout compact and readable in both light and dark menu bar appearances.
- Avoid excessive UI updates or visible flicker. Use monospaced digits (`.monospacedDigit()`) so the item's width stays stable across price updates and does not push neighboring menu bar items. The width still changes when the sign appears or disappears or the number of digits changes; that is acceptable.
- When data is stale, indicate it in the menu bar itself with a status symbol in front of the price (the SF Symbol `exclamationmark.triangle`), not only in the popover. Do not rely on dimmed text: the label renders as a template, so opacity may be ignored. A user who only glances at the menu bar must not read a stale price as live.
- When no data has been received, show a placeholder (for example, `₿ —`) instead of a price.
- `MenuBarExtra` labels honor only part of SwiftUI's modifiers. Verify during Milestone 0 that the label renders the composite content (status symbol, price, percentage) and honors `.monospacedDigit()`. If it does not, render the label as a template image with `ImageRenderer` (`isTemplate = true`), keeping its accessibility label (§6.5).

The app cannot detect how much menu bar space is available. The percentage toggle (§6.3) is the only mechanism to shorten the item. The item can also be hidden behind the camera notch when the menu bar is full, or by the user in the system's menu bar settings (macOS 26 and later). With no Dock icon and the single-instance check (§7), the app is then running but unreachable, and opening it again does nothing visible. The troubleshooting instructions (§11) must cover this case.

### 6.2 Popover

Clicking the menu bar item opens a compact popover (`MenuBarExtra` window style) showing:

- `BTC / USDT`
- `Binance Spot`
- Latest price
- 24-hour percentage change
- 24-hour high
- 24-hour low
- 24-hour BTC volume
- Connection state and data freshness (§5.7), in user-friendly words (table below)
- Last successful update time, or `—` before the first price
- The two preferences from §6.3, as toggles
- A **Quit** button. The app has no Dock icon, so this is the only way to quit it.

Before the first price, every market value (price, change, high, low, volume) shows `—`.

Status text (wording may be refined, the meaning may not). Derive it in one pure function of the connection state and the data freshness, outside the view, so it is unit-tested:

| State | Text |
|---|---|
| Connecting | Connecting to Binance… |
| Connected + No data | Connecting to Binance… |
| Connected + Live | Live |
| Connected + Stale | Waiting for data… |
| Reconnecting | Reconnecting… |
| Rate limited | Binance is limiting connections from your network |
| Offline | No internet connection |
| Unavailable | Binance is not available from your network or region |

When the data is Stale, the popover also states that the price shown is not current, in addition to the text above.

A connection that completes the handshake but never sends data alternates between "Connecting to Binance…" (Connected + No data) and "Reconnecting…" once per freshness threshold, as the watchdog reconnects (§5.6). This is expected.

The popover must remain compact and visually consistent with native macOS conventions.

### 6.3 Preferences

Keep v1 to exactly two preferences, shown as toggles directly in the popover. There is no separate Settings window.

- **Launch at login**, implemented with `SMAppService.mainApp`. The toggle reflects `SMAppService.mainApp.status` and is not stored in `UserDefaults`, because the system is the source of truth. Re-read the status every time the popover opens, because the user can change it in System Settings while the app runs. `MenuBarExtra` has no explicit open callback, and the content's `onAppear` may fire only on the first open: verify during Milestone 4 which signal fires on every open (for example, the popover window becoming key) and use it. If the status is `.requiresApproval`, tell the user to approve the app in System Settings → General → Login Items. If `register()` or `unregister()` throws, or the status is `.notFound` (for example, the app runs translocated, §11), set the toggle back to the status the system reports and show a short message in the popover; do not retry automatically.
- **Show 24h change in menu bar** (default: shown), stored with `@AppStorage`.

Do not add settings for exchange, symbol, currency, price precision, alerts, or chart intervals in v1.

### 6.4 Formatting

| Value | Format |
|---|---|
| Price | Locale-aware grouping, exactly 2 decimals (`BTCUSDT` tick size is 0.01) |
| 24h change | 2 decimals, explicit sign, `%` suffix. Round the value, format its absolute value as a plain decimal number, then prefix `+` if the rounded value is positive, `−` (U+2212 MINUS SIGN) if negative, and nothing if zero. Never use the formatter's own sign: it varies by locale. So `"-0.004"` displays as `0.00%`, without a sign. The decimal separator follows the locale, like the price; append `%` with no space in every locale (`+2,45%` in `pt_BR`) |
| 24h high / low | Same as price |
| 24h volume | Locale-aware grouping, 0 decimals, `BTC` suffix after a space (`12,345 BTC`) |
| Last update | Absolute local time with seconds, following the user's locale and 12/24-hour setting (for example, `14:32:07` or `2:32:07 PM`), so no timer is needed to refresh it. When the update is not from today (by the injected `now` source), prefix the locale's short date (for example, `Nov 5, 14:32:07`), so a price stale since yesterday is not read as today's. Re-evaluate this check each time the popover opens, using the same open signal as the launch-at-login status (§6.3): with stale data nothing else re-renders the popover, and the day can change while it stays open or hidden |

Format numbers with `Decimal.FormatStyle`, not `NumberFormatter`, and round half away from zero for every value (`.rounded(rule: .toNearestOrAwayFromZero)`): `"-2.455"` displays as `−2.46%`. Tests must pin the locale, the time zone, and the calendar, so formatting results are deterministic: the last-update time and its "not from today" check depend on all three.

### 6.5 Accessibility and appearance

- Support macOS light and dark appearances.
- Use semantic colors and system typography where possible.
- Provide accessible labels for menu bar and popover values. The stale status symbol (§6.1) has its own label, so VoiceOver never reads a stale price as current.
- Do not communicate connection state or data freshness through color alone.
- Ensure values remain readable at common menu bar scaling settings.

## 7. Application architecture

Keep the architecture small, testable, and independent of SwiftUI views.

Suggested responsibilities:

### `BitcoinTickerApp`

- Declares the `MenuBarExtra` scene.
- Allows a single instance. At launch, if another instance with the same bundle identifier is already running (`NSRunningApplication.runningApplications(withBundleIdentifier:)`), quit immediately. The list includes the current process: exclude it by comparing `processIdentifier` with `NSRunningApplication.current`, or the app quits on every launch. Quit only if another instance launched earlier (compare `launchDate`): otherwise two copies launched at the same moment each see the other and both quit. When the dates are equal or either is `nil`, the instance with the higher `processIdentifier` quits, so exactly one survives. Put this decision in a pure function of the current and the other instances' `processIdentifier` and `launchDate`, so it is unit-tested. Keep the menu bar item out (`MenuBarExtra(isInserted:)` bound to `false`) until the check passes, so a copy that quits never shows a second item, even briefly. Otherwise opening the app from the DMG and from `/Applications` would show two menu bar items and open two WebSocket connections.
- When the process is a unit-test host, starts neither the `MarketDataStore` nor the single-instance check, and does not insert the menu bar item (`MenuBarExtra(isInserted:)` bound to `false`): the scene is declared regardless of the store, so skipping the store alone still shows the item. The tests run inside the app (`@testable import`, §4), so otherwise every test run would connect to Binance, show a menu bar item, and quit itself while a Debug build is already running. Detect the test host with one signal verified during Milestone 0 (for example, the `XCTestConfigurationFilePath` environment variable), including under the Brazil test plan configuration (§5.3).

### `BinanceWebSocketClient` (actor)

- Owns the WebSocket connection and receive loop.
- Decodes incoming ticker messages through `BinanceTickerMessage`.
- Reports connection state and parsed events through an explicit interface (for example, an `AsyncStream`).
- Implements reconnection, backoff, fixed delays, and single-connection ownership (§5.5).
- Exposes `reconnect()` and `setNetworkAvailable(_:)` for the store (§5.5).
- Depends on an injectable WebSocket transport protocol, clock, and random source, so tests can run without the network.
- Does not import or depend on SwiftUI.

### `BinanceTickerMessage`

- Typed representation of the fields required from Binance.
- Validates the expected symbol and required values.
- Uses `Decimal` for financial values.

### `MarketDataStore` (`@MainActor`, `@Observable`)

- Starts and stops the client.
- Observes `NWPathMonitor` and `NSWorkspace.didWakeNotification` through injectable protocols, and calls `client.setNetworkAvailable(_:)` and `client.reconnect()` (§5.5).
- Exposes market data, connection state, and data freshness to the UI.
- Owns the freshness policy and the connection watchdog, driven by a single deadline task on the same injected clock as the client (§5.6).
- Keeps UI state separate from transport implementation.
- Publishes only meaningful changes where practical.

### `PriceFormatter`

- Formats price, percentage, volume, and timestamps according to §6.4.
- Uses locale-aware formatting. The quote currency appears once, in the popover's `BTC / USDT` header (§6.2); prices carry no currency suffix.
- Keeps formatting rules out of SwiftUI views.

### SwiftUI views

- `MenuBarView`: menu bar label.
- `PricePopoverView`: market summary, state, the two preference toggles, and the Quit button.

Use `@MainActor` for UI-facing observable state. Use actors or another clear isolation strategy for mutable networking state. Avoid shared mutable state without explicit concurrency guarantees.

## 8. Suggested project structure

The exact structure may be adapted to the Xcode project, but responsibilities should remain separated.

```text
BitcoinTicker/
├── App/
│   ├── BitcoinTickerApp.swift
│   └── SingleInstance.swift      (pure single-instance decision, §7)
├── Binance/
│   ├── BinanceWebSocketClient.swift
│   ├── BinanceTickerMessage.swift
│   ├── ConnectionState.swift     (connection state, §5.7)
│   ├── WebSocketTransport.swift          (transport protocol, §5.5)
│   └── URLSessionWebSocketTransport.swift (URLSession implementation and its delegate)
├── Market/
│   ├── MarketDataStore.swift
│   ├── DataFreshness.swift   (data freshness, §5.7; owned by the store, §7)
│   ├── PriceFormatter.swift
│   ├── StatusText.swift      (pure status-text function, §6.2)
│   └── SystemEvents.swift    (network-path and wake protocols with their NWPathMonitor and NSWorkspace implementations)
├── Support/
│   └── Dependencies.swift    (clock and random-source abstractions, §5.5)
├── UI/
│   ├── MenuBarView.swift
│   └── PricePopoverView.swift
├── Resources/               (AppIcon asset)
└── BitcoinTicker.entitlements (App Sandbox + network client, §10; absent if the template sets them through `ENABLE_*` build settings)
BitcoinTicker.xctestplan     (default configuration + one with language Portuguese (Brazil), region Brazil, and `EXPECT_COMMA_DECIMAL=1`, §5.3)
BitcoinTickerTests/          (separate Xcode test target)
├── AppTests/                (single-instance decision)
├── BinanceTests/
├── MarketTests/             (store, freshness, formatter)
└── Fakes/                   (manual clock, fake transport, random source, path and wake sources)
```

## 9. Error handling and observability

The app is a local utility and should not collect analytics or send diagnostic data to a third party.

Handle at least:

- No network connection.
- WebSocket handshake failure.
- Handshake rejected by Binance: regional restriction (451/403) or rate limit/ban (429/418).
- Remote close or connection timeout.
- Half-open connection (no messages, no close).
- Malformed JSON.
- Missing or invalid ticker fields.
- Unexpected symbol.
- Stale market data.
- App wake from sleep.
- Repeated reconnect failures.

Use structured, low-volume local logging (for example, Apple's `Logger`) for actionable diagnostics. Use the subsystem `io.github.allisson.BitcoinTicker` as a constant in every configuration, not `Bundle.main.bundleIdentifier`: the Debug identifier has a `.debug` suffix (§4), and log filters must match both builds. Log every connection-state change and every data-freshness transition (No data → Live, Live → Stale, Stale → Live): the Milestone 5 continuous run relies on them to show that the price stayed Live through Binance's 24-hour close. Log them at `.notice` level or above, with `privacy: .public` on the state names: `.info` and `.debug` messages are not persisted by default, and interpolated strings are redacted as `<private>`. Log individual ticker messages, if at all, only at `.debug`, so the persisted log stays low-volume. A network path flapping faster than the minimum attempt interval (§5.5) still logs each Offline change; this is accepted, because such flapping is rare and short. Never log secrets; v1 has no credentials to log.

The UI should communicate state in user-friendly terms rather than exposing raw networking errors.

## 10. Privacy and security

- Use only Binance's public market-data endpoint.
- Do not request or store Binance credentials.
- Do not request access to files, contacts, location, microphone, camera, or other unrelated user data.
- Do not include analytics, advertising, tracking, or a remote configuration service.
- Use HTTPS/WSS.
- Keep network access limited to the Binance endpoint required for market data.
- Enable App Sandbox with only the `com.apple.security.network.client` entitlement. The Xcode app template also enables read-only access to user-selected files (`ENABLE_USER_SELECTED_FILES = readonly`, or `com.apple.security.files.user-selected.read-only` in a generated `.entitlements` file): remove it.
- Do not disable App Transport Security.
- Document that the application displays exchange-provided market data and is not a trading or investment service.

## 11. Distribution

The first release is distributed outside the Mac App Store:

- Build a Universal (Apple Silicon and Intel) release `.app`. Xcode 27 runs only on Apple silicon and macOS 27 drops Intel Macs, but with the macOS 14 deployment target the build stays Universal by default, and Intel Macs run macOS 14 to 26. Nothing on the build Mac exercises the Intel slice unless it is launched under Rosetta.
- Include an app icon. Finder, the DMG, and Login Items in System Settings show it.
- v1 does not require an Apple Developer Program membership. The app is not signed with Developer ID and is not notarized.
- Sign the app ad hoc (Xcode "Sign to Run Locally", equivalent to `codesign --sign -`). Apple Silicon does not run arm64 code without at least an ad hoc signature.
- Keep hardened runtime and App Sandbox enabled. Never weaken them to make the build run.
- Version with `MARKETING_VERSION` in semantic versioning (`1.0.0` for v1) and `CURRENT_PROJECT_VERSION` as an integer incremented for every published build. The Git tag is `v<MARKETING_VERSION>` and the DMG is `BitcoinTicker-<MARKETING_VERSION>.dmg`. Pre-releases published to test a build add `-rc.<CURRENT_PROJECT_VERSION>` to both (`v1.0.0-rc.2`, `BitcoinTicker-1.0.0-rc.2.dmg`), so every published build has its own tag. The release itself gets the plain tag on the promoted pre-release's commit, with that same DMG renamed (renaming does not change its checksum).
- Publish a versioned DMG through GitHub Releases, with its SHA-256 checksum in the release notes. Without a Developer ID signature, the checksum is the only way a user can check that the download is intact. It does not prove authenticity, because it is published on the same page as the DMG.
- Include installation, manual update, and uninstall instructions, in the README and the release notes (the download page, read before the first launch). The DMG holds only the app and a link to `/Applications`. Uninstall: turn off Launch at login before deleting the app, so no stale login item is left behind, then delete the app and its sandbox container (`~/Library/Containers/io.github.allisson.BitcoinTicker`), which holds the stored preference. Verify during Milestone 5 that the container can be deleted this way; if macOS blocks it or asks for permission, document the steps that actually work.

**Gatekeeper.** A downloaded app is quarantined, and Gatekeeper blocks its first launch because it is not notarized. The installation instructions must cover:

- First, drag the app to `/Applications` before opening it. An app opened from the DMG or from Downloads runs translocated, from a random read-only path, and launch at login (§6.3) would register that path.
- macOS 14: right-click the app → Open → Open.
- macOS 15 or later: open the app once, then System Settings → Privacy & Security → Open Anyway. The button is offered only for about an hour after the blocked launch; after that, open the app again first. Right-click → Open no longer works there.
- Advanced alternative: `xattr -dr com.apple.quarantine "/Applications/Bitcoin Ticker.app"`.

**Updates.** Each build gets a new ad hoc signature, so macOS may treat every release as a different app: the Gatekeeper approval repeats after each update, and the launch-at-login registration (§6.3) may need to be turned off and on again. The App Sandbox container is also tied to the code signature: on macOS 14 or later, the new build may trigger a prompt to access data from other apps, or lose access to the container and with it the stored preference (§6.3). Verify all of this before the release and document what actually happens.

**Troubleshooting.** The README and the release notes must cover, at least, a menu bar item that does not appear (§6.1): turn off "Show 24h change", or quit other menu bar apps, to free space next to the notch; check that the item is allowed in the system's menu bar settings (macOS 26 and later); quit the running copy from Activity Monitor if it cannot be reached. Also cover the Unavailable state (regional availability, §5.2).

Developer ID signing and notarization are post-v1 backlog.

## 12. Acceptance criteria for v1

The release is acceptable when all of the following are true. A criterion that a known limitation recorded in Milestone 1 (in the roadmap's verification log) makes impossible (an unreadable upgrade status, §5.2) counts as met when the limitation is stated in the README and the release notes.

1. The app launches as a menu bar utility without a Dock icon or a normal main window.
2. It connects to Binance Spot public WebSocket for `BTCUSDT` without credentials.
3. It displays the latest valid ticker price in the menu bar.
4. It displays the 24-hour percentage change by default, and hides it when the user turns the preference off.
5. The popover displays price, 24-hour change, high, low, volume, connection state, data freshness, and last update time, formatted per §6.4.
6. It visibly distinguishes live data from stale or missing data, in the menu bar and in the popover.
7. VoiceOver reads the menu bar item and the popover values, including the stale status, so a stale price is never read as current (§6.5).
8. It reconnects after network loss using backoff capped at 60 seconds, and immediately when the network path returns, unless a fixed delay is pending (§5.5).
9. It does not create duplicate WebSocket connections during normal lifecycle transitions, including Binance's 24-hour close and a second launch of the app (§7), and the price stays Live through the 24-hour close.
10. It handles malformed or unexpected messages without crashing.
11. It recovers after the Mac wakes from sleep.
12. It shows the Unavailable state when Binance rejects the handshake with 451 or 403, including after the network path returns during the fixed delay. After a 451, 403, 429, or 418 rejection, it retries only after the fixed delay (§5.5), including while data is stale, when the network path returns, and after wake. After a 429 or 418 rejection, the popover shows that Binance is limiting connections (§6.2).
13. The user can quit the app from the popover.
14. The launch-at-login toggle registers and unregisters the app with `SMAppService.mainApp`, and reflects the system status after a relaunch.
15. Core parsing, formatting, state, status text, freshness, and reconnect behavior are covered by automated tests.
16. The app does not require a Binance API key or any application backend.
17. Between ticker messages the app does no work besides the store's deadline task (§5.6) and the client's pending sleeps (handshake timeout, backoff, fixed delay; §5.5): no polling, confirmed with Instruments.
18. A DMG containing the ad hoc signed Universal app, its SHA-256 checksum, and installation instructions covering the Gatekeeper steps for macOS 14 and macOS 15 or later (§11), is available in GitHub Releases.

## 13. Product principles

- **Small scope:** solve one problem exceptionally well.
- **Native first:** use macOS APIs rather than embedding a web application.
- **Direct data:** connect to Binance public market data without a middleman.
- **Honest status:** never imply stale data is live.
- **Low overhead:** minimize CPU, memory, network traffic, and UI churn.
- **Testable boundaries:** isolate networking, parsing, state, and presentation.
