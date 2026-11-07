# AGENTS.md

Native macOS menu bar app that shows the live Binance Spot `BTCUSDT` price from Binance's public
WebSocket. No API key, no account, no backend, no third-party dependencies.

## Source of truth

- `docs/spec.md`: product behavior and technical constraints. It wins over everything else,
  including this file.
- `docs/roadmap.md`: milestone order (M0 → M5), tests per milestone, and the verification log (§9).
- Before coding, read the spec sections the milestone item points to. Do not restate spec rules
  in code comments or other docs; reference the section (`spec §5.5`).
- If the repository, the roadmap, and the spec disagree, stop and report the conflict.

## Current state

All milestones (0 to 5) are done and v1.0.0 is published on GitHub Releases. By maintainer
decision, the 24-hour run was replaced by a periodic-close check, and nothing was verified on
macOS 14, 15, or 27 (`docs/roadmap.md` §9). New work starts from `docs/roadmap.md` §7 (post-v1
backlog) only with the maintainer's approval.
Update this section when a milestone is completed.

- `BitcoinTickerApp` creates the store in every process and starts it only outside a unit-test
  host; the views read it directly.
- The popover's `onAppear` fires on every open (`docs/roadmap.md` §9): it re-reads the
  launch-at-login status and the date for the last-update prefix.
- Turning Launch at login on in a Debug build registers its DerivedData path: turn it off before
  deleting that build.
- Client tests use `ClientHarness` (`BinanceWebSocketClientTests.swift`) and store tests use
  `StoreHarness` (`MarketDataStoreTests.swift`): wait for a sleeper with `hasSleeper(at:)` or for a
  state before advancing the manual clock, or the test races the code under test.
- `xcodebuild build` of Debug drops the test bundle from the app, so run `xcodebuild test` (not
  `test-without-building`) after it.

- Xcode 27 turns hardened runtime off in Debug builds, and a plain `xcodebuild build` of Release
  carries `get-task-allow`. Check signing on the archived `.app` only.

## Scope

- v1 is exactly what `docs/spec.md` §2.1 and §12 describe. Do not add anything from §2.2
  (non-goals), §6.3 (settings not to add), or `docs/roadmap.md` §7 (post-v1 backlog) without
  approval.
- Exactly two preferences, both in the popover: Launch at login and Show 24h change. No Settings
  window.

## Stack and settings (spec §4)

- Swift 6 language mode, Xcode 26 or later, macOS 14 deployment target.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (not the template's `MainActor`) and
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`, both set explicitly.
- SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)`, `LSUIElement = YES`, Observation
  (`@Observable`), Swift Testing.
- Bundle identifier `io.github.allisson.BitcoinTicker` (Debug adds `.debug`). Never change it.
- App Sandbox with only `com.apple.security.network.client`, hardened runtime, ad hoc signing
  ("Sign to Run Locally"). Never weaken any of them to make something work.

## Architecture (spec §7, §8)

- `BinanceWebSocketClient` (actor): connection, receive loop, backoff, fixed delays,
  `reconnect()`, `setNetworkAvailable(_:)`. No SwiftUI import.
- `BinanceTickerMessage`: parsing and validation (spec §5.3).
- `MarketDataStore` (`@MainActor`, `@Observable`): freshness, watchdog, one deadline task,
  `NWPathMonitor` and wake observation.
- `PriceFormatter` and the status-text function: pure, outside the views.
- Transport, clock, random source, path and wake sources are injected behind small protocols.
  Tests use fakes and a hand-written manual clock in the test target, never the real network or
  real time.

## Rules that are easy to get wrong

- Money and percentages are `Decimal`, never `Double`. Validate each numeric string with
  `wholeMatch` against the spec §5.3 pattern and the 32-character limit before
  `Decimal(string:locale: nil)`.
- `P` is already in percentage points: never multiply by 100.
- Freshness uses `ContinuousClock` (injected), not Binance's `E` field and not `SuspendingClock`.
- The negative sign is U+2212, added by our code, never the formatter's own sign.
- Only one connection and one receive loop at a time; discard messages from a closed or replaced
  connection.
- Path changes and wake never shorten a fixed delay. The retry rules are in spec §5.5, with a
  summary table at its end.
- Logging: `Logger` with the constant subsystem `io.github.allisson.BitcoinTicker`; state and
  freshness changes at `.notice` with `privacy: .public`; ticker messages only at `.debug`.
- The app must start neither the store, the single-instance check, nor the menu bar item when it
  runs as a unit-test host (spec §7).

## Commands

Run from the repository root. Build output and release artifacts go in `build/` (ignored by Git).

```sh
# Build the Debug app
xcodebuild build -project BitcoinTicker.xcodeproj -scheme BitcoinTicker -configuration Debug -derivedDataPath build/DerivedData

# Run the full test plan (Default and Brazil configurations); the output is long, so keep a log
xcodebuild test -project BitcoinTicker.xcodeproj -scheme BitcoinTicker -testPlan BitcoinTicker -derivedDataPath build/DerivedData > build/test.log 2>&1; grep -E 'Test run with|TEST (SUCCEEDED|FAILED)|✘' build/test.log

# Follow the app's logs, ticker messages included
log stream --level debug --predicate 'subsystem == "io.github.allisson.BitcoinTicker"'

# Launch the Debug build; from M1 on, point it at a local test server
open "build/DerivedData/Build/Products/Debug/Bitcoin Ticker.app" --args -BinanceURL ws://127.0.0.1:8080
```

The sandboxed app logs `com.apple.linkd.autoShortcut` connection errors under tests; they are
system noise, not test failures.

CI (`.github/workflows/ci.yml`) runs the same test plan with Xcode 26.6 on every pull request to
`main`. Code must build with Xcode 26 and with the newer Xcode used locally: do not rely on
language features or APIs that Xcode 26 lacks.

## Commits

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<scope>): <description>

<body: why, when the description is not enough>

<footers>
```

- Types: `feat`, `fix`, `test`, `refactor`, `perf`, `docs`, `build`, `ci`, `chore`, `revert`.
  Code and its tests go in the same commit, typed by the code (`feat`, `fix`), not `test`.
- Scope (optional) names the area: `app`, `client`, `parser`, `store`, `formatter`, `ui`,
  `prefs`, `release`, or `deps`. Omit it when a change spans several.
- Description: English, imperative, lowercase, no final period, header at most 72 characters.
- Breaking change: `!` after the type or scope, and a `BREAKING CHANGE:` footer.
- One logical change per commit; a roadmap step may take several.

Examples:

```text
build(app): create Xcode project with sandbox and nonisolated default isolation
feat(parser): validate ticker numeric strings before Decimal parsing
fix(client): keep fixed delay pending when the network path returns
docs: record M1 transport verification in the roadmap
```

Release tags follow spec §11 (`v1.0.0`, `v1.0.0-rc.2`), not the commit types.

## Working agreement

- Follow the implementation order in `docs/roadmap.md` §4. Keep the project buildable after every
  step, and write tests in the same step as the code.
- Tick the roadmap checkboxes as items are done, and fill the verification log (`docs/roadmap.md`
  §9) for every manual check. Never mark an item done without running or verifying it.
- Manual checks that need hardware, other macOS versions, VoiceOver, or a 25-hour run: say they are
  pending instead of guessing a result.
- Ask before decisions that change architecture or user-visible behavior.
- Nothing leaves the machine without approval: no `git push`, tags, GitHub Releases, or pull
  requests unless the maintainer asks.
