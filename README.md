# ClaudeUsageNotch

A native macOS app that displays Claude Code usage (session + weekly quota) live in the hardware notch.

The notch panel works like iOS Dynamic Island: the top portion sits inside the physical camera housing (black on black), and only the visible extension below is rendered. Hover to expand; click to pin open.

---

## Build

For local iteration, `./build.sh` from the repo root kills any running instance, builds a signed binary (Mode A, with the maintainer's `SIGN_IDENTITY` baked in), and relaunches the app. For a from-scratch build or a different signing identity, use the modes below directly.

**Mode A — no Xcode required (default)**

```bash
cd swift-project/ClaudeUsageNotch
bash scripts/build.sh
open build/ClaudeUsageNotch.app
```

Compiles with `swiftc` directly. Produces an ad-hoc signed binary for local use only. Do not distribute Mode A builds.

To sign with a real Developer certificate (recommended — fixes Keychain ACL prompts on wake):

```bash
# list available certs
security find-identity -v -p codesigning

SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" bash scripts/build.sh
```

With a stable identity, macOS permanently honors "Always Allow" on the `Claude Code-credentials` Keychain item across rebuilds and sleep/wake cycles. Without it, the prompt recurs.

**Mode B — xcodebuild**

```bash
brew install xcodegen
cd swift-project/ClaudeUsageNotch
USE_XCODEBUILD=1 bash scripts/build.sh
open build/ClaudeUsageNotch.app
```

Generates an Xcode project via XcodeGen, then builds with `xcodebuild`. Required for code signing and notarization. See `scripts/sign_and_notarize.sh`.

**Intel Mac:** change `-target arm64-apple-macosx26.0` to `-target x86_64-apple-macosx26.0` in `scripts/build.sh`.

**Xcode development:**

```bash
brew install xcodegen
cd swift-project/ClaudeUsageNotch
xcodegen generate
open ClaudeUsageNotch.xcodeproj
```

---

## Requirements

- macOS 12.0+ (arm64; Intel works with target swap above)
- MacBook with a hardware notch
- Xcode CLI tools (`xcode-select --install`)
- Full Xcode + `brew install xcodegen` for Mode B only

---

## Architecture

```
Sources/
├── App/
│   ├── ClaudeUsageNotchApp.swift  @main SwiftUI entry point
│   └── AppDelegate.swift          Wires AppState, NotchWindowController, UsageCoordinator
│
├── Core/
│   ├── Domain/
│   │   ├── ServiceUsageSnapshot.swift
│   │   ├── UsageRecord.swift      Token-level record parsed from JSONL history
│   │   ├── UsageWindow.swift      Session / weekly windows, pace, reset helpers
│   │   ├── Status.swift           UsageStatus, ProviderError, AuthStatus, SyncStatus
│   │   ├── AnalyticsData.swift    Cost/token/model/project/skill breakdowns for the analytics chart
│   │   ├── QuotaSnapshotPayload.swift  Payload POSTed to the sync server's quota_snapshots table
│   │   └── AgentStatus.swift      Aggregated local Claude Code session status (idle/working/needsInput)
│   └── State/
│       ├── AppState.swift         Runtime state; snapshots, notch state, incidents
│       │                          Also defines ExpandedMode (.usage | .analytics | .settings)
│       ├── AppSettings.swift      Persisted prefs: poll interval, thresholds, notifications
│       └── NotchState.swift       compactIdle / expandedHover / expandedPinned / …
│
├── Providers/
│   └── Claude/
│       ├── ClaudeProvider.swift   OAuth + cookie auth; session + weekly fetch
│       ├── ClaudeCredential.swift
│       ├── ClaudeOAuthCredential.swift
│       ├── ClaudeEndpoint.swift
│       └── ClaudeUsageDTO.swift
│
├── Services/
│   ├── UsageService.swift         Polling loop + exponential backoff
│   ├── UsageCoordinator.swift     UsageService → AppState → NotificationService
│   ├── AuthService.swift          Keychain + CLI OAuth detection
│   ├── NotificationService.swift  In-app banners at configurable thresholds
│   ├── LocalHistoryReader.swift   Reads ~/.claude/projects/**/*.jsonl; feeds the sync push
│   ├── RemoteHistoryReader.swift  Fetches pre-aggregated analytics from the sync server (the chart's only source)
│   ├── HistorySyncService.swift   Timer-driven push of local records to the sync server
│   ├── QuotaSyncService.swift     Pushes each polled session/weekly % to the sync server (ground truth for the chart)
│   ├── IncidentMonitor.swift      Polls Anthropic status page
│   └── AgentStatusService.swift   Polls the agent-status-hook status file
│
├── Platform/
│   ├── KeychainStore.swift
│   └── ScreenUtils.swift          Notch screen detection, panel positioning, dynamic compact width
│
└── UI/
    ├── NotchWindowController.swift  Borderless NSPanel; hover timer; width animation
    ├── NotificationBanner.swift
    ├── Compact/
    │   ├── CompactView.swift        Dual bars; countdown at session limit
    │   ├── CompactProgressBar.swift Pace marker tick
    │   ├── StatusDot.swift          StatusBubble (inline outage / sync pill)
    │   └── AgentStatusGlow.swift    Perimeter pulse for agent status (compact-idle only)
    ├── Expanded/
    │   ├── ExpandedPanelView.swift  Switches on ExpandedMode
    │   ├── ExpandedPanelGeometry.swift  Panel width/height per mode; shared with NotchWindowController
    │   ├── HeaderRow.swift          Provider name, sync time, mode buttons, quit
    │   ├── SessionCard.swift
    │   ├── WeeklyCard.swift
    │   ├── ResetSubtitleRow.swift   Countdown · reset time/date · expected usage
    │   ├── UsageChartView.swift     Cost/token analytics: model/project/skill breakdowns, daily & hourly charts
    │   └── InlineSettingsView.swift Settings rendered inline in the notch panel
    ├── Onboarding/OnboardingView.swift
    └── Theme/                       Theme · BrandIcon · GlassBackground/NotchPillShape · RetroMascot
```

---

## Data flow

```
AuthService (Keychain / CLI OAuth)
    │
    ▼
UsageService (poll loop + backoff)
    │
    ├─ snapshotPublisher ──► UsageCoordinator ──► AppState.snapshots
    │                                         ├──► NotificationService.evaluate(...)
    │                                         └──► QuotaSyncService.push ──POST──► sync server (when apiBaseURL set)
    │
    └─ errorPublisher ────► UsageCoordinator ──► AppState.providerErrors / syncStatus
                                                       │
    IncidentMonitor ────────────────────────────────► AppState.incidents
                                                       │
                                                       ▼
                                              SwiftUI views (CompactView, ExpandedPanelView, …)

~/.claude/projects/**/*.jsonl
    │
    └─ LocalHistoryReader ──► HistorySyncService (timer) ──POST──► sync server   (when apiBaseURL set)

UsageChartView (analytics mode only; not part of the poll loop)
    └─ RemoteHistoryReader.fetchAnalytics ──GET──► sync server   (pre-aggregated; requires apiBaseURL)
```

`AppState` is the primary `ObservableObject` for runtime data. `AppSettings` holds persisted preferences separately so settings changes don't re-trigger usage observers.

The analytics chart does not poll — on switching to analytics mode it fetches pre-aggregated analytics from the sync server (see [Sync server](#sync-server-optional)), with a 60-second in-memory cache to avoid re-fetching on hover-away/return.

---

## Expanded panel modes

`ExpandedMode` (defined in `AppState.swift`) controls what the expanded panel shows:

| Mode | Content |
|------|---------|
| `.usage` | Session card + weekly card + reset countdown |
| `.analytics` | Cost/token breakdowns by model, project, and skill, plus daily/hourly activity charts (`UsageChartView`, backed by `AnalyticsData`) |
| `.settings` | Inline settings: poll interval, notification thresholds, hide toggle |

Mode buttons live in `HeaderRow`. Settings are no longer a separate window — they render directly in the notch panel.

---

## How the notch window works

`NotchWindowController` creates a borderless, non-activating `NSPanel` at window level `.popUpMenu` (101 — above the macOS menu bar compositor). The panel anchors at `screen.frame.maxY`. Its height is `safeAreaInsets.top` (~37 pt on MBP 14/16") plus the visible content height.

Hover detection uses a 40 ms `Timer` polling `NSEvent.mouseLocation` — `NSTrackingArea` and global event monitors are unreliable on non-activating panels.

When the session hits 100%, the compact panel widens via `ScreenUtils.compactPanelWidth` so countdown text (e.g. `2h 1m`) stays in the visible strip beside the camera cutout.

---

## Auth

Claude auth is tried in this order:

1. **CLI OAuth** — `Claude Code-credentials` Keychain item or `~/.claude/credentials.json`
2. **Session cookie** — pasted from a claude.ai browser session, stored in Keychain

Onboarding skips the cookie step when CLI OAuth is detected.

The `Claude Code-credentials` Keychain item is owned by the Claude CLI, so reading it
is a cross-app access that prompts whenever the CLI rewrites the item on token refresh
(a rewrite resets its ACL). To avoid prompting on every poll, `ClaudeOAuthCredential`
mirrors a successful read into an app-owned Keychain item and reads from that mirror
while the token is unexpired, only falling back to the CLI item (and a possible prompt)
once the mirrored token rotates. The mirror stays silent across rebuilds **only with a
stable code signature** — build with `SIGN_IDENTITY` set, not an ad-hoc Mode A build.
`UsageService` also retries auth failures on a short fixed interval instead of its
exponential backoff, so the access prompt re-surfaces in seconds rather than minutes.

---

## State persistence

`AppSettings` persists to `UserDefaults` under `claudeusagenotch.*`: poll interval, notification toggle, thresholds, sync server URL (`apiBaseURL`), and `syncIntervalSeconds`.

`HistorySyncService` persists its `lastSyncedAt` cursor under the same prefix.

`AppState` persists `isNotchUIHidden`. Snapshots are not persisted — the app fetches fresh on launch.

---

## Agent status pulse (optional)

A thin animated stroke around the notch perimeter, visible only in the compact,
unhovered state (`NotchState.compactIdle`), reflecting the most-actionable state
across your local Claude Code CLI sessions: amber pulse = a session needs your
input, cyan pulse = a session is working, steady green = a session finished
within the last 30 s (suppressed while any other session is working or waiting,
so it can never mask one that needs you). It disappears the instant you hover,
and stays off entirely when no session is active. Toggle it off in Settings ("Agent Status Pulse") without
affecting the rest of the app.

This only sees **local** CLI sessions on this Mac — there's no visibility into
remote/cloud-hosted sessions.

**Mechanism.** `agent-status-hook/hook.py` (stdlib-only Python) is invoked by
Claude Code hooks and read-modify-writes a small JSON file at
`~/Library/Application Support/ClaudeUsageNotch/agent-status.json`, keyed by
`session_id`. `AgentStatusService` polls that file (~1.5 s), drops entries that
are stale and non-idle (a session that never sent `Stop`/`SessionEnd` — e.g. a
killed terminal — so it can't hold `working`/`needsInput` forever), and
aggregates the rest with `needsInput` > `working` > `idle` priority so a session
waiting on you is never hidden behind one that's merely working.

The `Notification` event only fires amber for genuine tool-permission prompts.
For a turn that ends on a plain informational ask with no interactive prompt
(e.g. "VPN looks disconnected, can you reconnect it?"), the hook's `Stop`
handler reads the transcript's last assistant message and also fires amber if
it contains the literal marker `[NEEDS-ACTION]`. Global CLAUDE.md instructs
Claude to append that marker when a turn ends on something only the user can
do outside the chat.

To enable it, add this to `~/.claude/settings.json` (adjust the path to where
you cloned this repo):

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "python3 /path/to/ClaudeUsageNotch/agent-status-hook/hook.py" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "python3 /path/to/ClaudeUsageNotch/agent-status-hook/hook.py" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "python3 /path/to/ClaudeUsageNotch/agent-status-hook/hook.py" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "python3 /path/to/ClaudeUsageNotch/agent-status-hook/hook.py" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "python3 /path/to/ClaudeUsageNotch/agent-status-hook/hook.py" }] }]
  }
}
```

If you already have hooks configured for these events, append to the existing
arrays rather than replacing them.

---

## Sync server (optional)

`claude-usage-notch-server/` is a companion Flask + SQLite service (runs on a Raspberry
Pi) that stores `UsageRecord`s parsed from the local JSONL history, so analytics can
outlive the ~30-day JSONL retention and load faster than re-parsing local files. It
stores raw records and serves them back, and aggregates them on demand for the chart via
`GET /api/analytics` (the server-side aggregation that previously ran in Swift). See its
README for the API.

Sync is **off by default** and enabled by setting a base URL in the inline settings
(e.g. `http://raspberrypi.local:5014`); an empty URL disables it entirely.

- **Producer** — `HistorySyncService` POSTs new records on a timer (`syncIntervalSeconds`,
  default 10 min). A `lastSyncedAt` cursor (in `UserDefaults`) only advances on a `200`,
  so failed pushes retry next tick; the server dedupes by `uuid`, making retries safe.
- **Consumer** — `UsageChartView` fetches pre-aggregated analytics from
  `GET /api/analytics` via `RemoteHistoryReader.fetchAnalytics` (5 s timeout). There is
  **no** local fallback: with no `apiBaseURL`, or an unreachable Pi, the chart shows
  nothing/an error rather than re-parsing local JSONL.

`UsageRecord` is `Codable` against the server's snake_case schema; local JSONL parsing
stays manual in `LocalHistoryReader` because the on-disk keys differ from the API's.

Multiple laptops can point at the same server with no extra setup: `UsageRecord.uuid`
is assigned by Claude itself (not generated locally), so each device's local history
merges into one deduped table regardless of which machine produced a given turn.

### Quota snapshots — real history for the % Quota chart

On every successful poll, `QuotaSyncService` POSTs the live `five_hour`/`seven_day`
utilization straight to `quota_snapshots` (`source` = hostname, useful when several
laptops poll the same account). `GET /api/analytics` returns this as
`session_quota_history` / `weekly_quota_history`; `UsageChartView`'s "% Quota" toggle
plots it as a step function (each reading held until the next one), falling back to a
token-share estimate only where no real reading exists yet (history predating this
feature, or before the app has been open long enough to cover the chart's lookback).

---

## Note

Claude's usage endpoints are undocumented and may break on API changes.

---

## License

MIT
