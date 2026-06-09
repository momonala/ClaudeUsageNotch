# ClaudeUsageNotch

A native macOS app that shows Claude Code usage (session + weekly quota) live in the hardware notch.

The notch panel works like iOS Dynamic Island: the top portion sits inside the physical camera housing (black on black), and only the visible extension below is rendered. Hover expands it; click pins it open.

---

## Build

**Mode A — no Xcode required (default)**

```bash
cd swift-project/ClaudeUsageNotch
bash scripts/build.sh
open build/ClaudeUsageNotch.app
```

Compiles with `swiftc` directly. Produces an **unsigned, ad-hoc signed** binary for local use only. Do not distribute Mode A builds.

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
│   │   ├── ProviderId.swift       Supported providers (currently: .claude)
│   │   ├── ServiceUsageSnapshot.swift
│   │   ├── UsageRecord.swift      Token-level record parsed from JSONL history
│   │   ├── UsageWindow.swift      Session / weekly windows, pace, reset helpers
│   │   └── Status.swift           UsageStatus, ProviderError, AuthStatus, SyncStatus
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
│   ├── LocalHistoryReader.swift   Reads ~/.claude/projects/**/*.jsonl for analytics
│   └── IncidentMonitor.swift      Polls Anthropic status page
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
    │   ├── ConstellationView.swift  Multi-provider layout (not wired yet)
    │   └── StatusDot.swift          IncidentBanner
    ├── Expanded/
    │   ├── ExpandedPanelView.swift  Switches on ExpandedMode
    │   ├── HeaderRow.swift          Provider name, sync time, mode buttons, quit
    │   ├── SessionCard.swift
    │   ├── WeeklyCard.swift
    │   ├── ResetSubtitleRow.swift   Countdown · reset time/date · expected usage
    │   ├── UsageChartView.swift     Bar chart of token consumption; session + weekly views
    │   └── InlineSettingsView.swift Settings rendered inline in the notch panel
    ├── Onboarding/OnboardingView.swift
    └── Theme/                       Theme · BrandIcon · NotchPillShape · RetroMascot
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
    │                                         └──► NotificationService.evaluate(...)
    │
    └─ errorPublisher ────► UsageCoordinator ──► AppState.providerErrors / syncStatus
                                                       │
    IncidentMonitor ────────────────────────────────► AppState.incidents
                                                       │
                                                       ▼
                                              SwiftUI views (CompactView, ExpandedPanelView, …)

LocalHistoryReader (reads ~/.claude/projects/**/*.jsonl on demand)
    └─► UsageChartView (analytics mode only; not part of the poll loop)
```

`AppState` is the primary `ObservableObject` for runtime data. `AppSettings` holds persisted preferences separately so settings changes don't re-trigger usage observers.

The analytics chart does not poll — it reads local JSONL history when the user switches to analytics mode, with a 60-second in-memory cache to avoid re-parsing on hover-away/return.

---

## Expanded panel modes

`ExpandedMode` (defined in `AppState.swift`) controls what the expanded panel shows:

| Mode | Content |
|------|---------|
| `.usage` | Session card + weekly card + reset countdown |
| `.analytics` | Bar chart of token consumption over session or week (`UsageChartView`) |
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

---

## State persistence

`AppSettings` persists to `UserDefaults` under `claudeusagenotch.*`: poll interval, notification toggle, thresholds.

`AppState` persists `activeProvider`, `enabledProviders`, and `isNotchUIHidden`. Snapshots are not persisted — the app fetches fresh on launch.

---

## Note

Claude's usage endpoints are undocumented and may break on API changes.

---

## License

MIT
