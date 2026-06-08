# ClaudeUsageNotch

A native macOS menubar app that shows Claude Code usage (session + weekly quota) live in the hardware notch. No Dock icon. No Electron. Under 10MB.

The notch panel works like iOS Dynamic Island: the top portion of the panel sits inside the physical camera housing (black on black), and only the visible extension below the notch is rendered. Hover expands it; click pins it open.

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
- Xcode CLI tools (`xcode-select --install`)
- Full Xcode + `brew install xcodegen` for Mode B only

---

## Architecture

```
Sources/
├── App/
│   ├── ClaudeUsageNotchApp.swift  @main SwiftUI entry point
│   └── AppDelegate.swift          Root controller; wires AppState, NotchWindowController, UsageCoordinator
│
├── Core/
│   ├── Domain/
│   │   ├── ProviderId.swift       Enum of supported providers (currently: .claude)
│   │   ├── ServiceUsageSnapshot.swift  Single point-in-time snapshot from a provider
│   │   ├── UsageWindow.swift      Session / weekly window with percent, reset time, status
│   │   └── Status.swift           UsageStatus (.healthy/.warning/.critical), ProviderError, AuthStatus
│   └── State/
│       ├── AppState.swift         Single ObservableObject source of truth; persists to UserDefaults
│       └── NotchState.swift       Enum: compactIdle / expanded / etc.
│
├── Providers/
│   ├── UsageProvider.swift        Protocol — implement this to add a provider
│   ├── ProviderRegistry.swift     Singleton registry; bootstrap() registers concrete providers
│   └── Claude/
│       ├── ClaudeProvider.swift   Fetches session + weekly usage from api.anthropic.com
│       ├── ClaudeCredential.swift Cookie-based credential (Keychain-backed)
│       ├── ClaudeOAuthCredential.swift  CLI OAuth token (Keychain item or ~/.claude/credentials.json)
│       ├── ClaudeEndpoint.swift   URL + header construction
│       └── ClaudeUsageDTO.swift   Decodable DTOs for the usage response
│
├── Services/
│   ├── UsageService.swift         Per-provider polling Tasks; exponential backoff on errors
│   ├── UsageCoordinator.swift     Connects UsageService → AppState → NotificationService
│   ├── AuthService.swift          Credential read/write via KeychainStore; Claude OAuth detection
│   ├── NotificationService.swift  In-app banners at configurable thresholds (default: 25/50/75/90%)
│   └── IncidentMonitor.swift      Polls provider status pages; writes to AppState.incidents
│
├── Platform/
│   ├── KeychainStore.swift        Thin wrapper around SecItem* APIs
│   ├── SQLiteReader.swift         Read-only SQLite access (used by some provider credential paths)
│   ├── NotchDetector.swift        Detects whether the current Mac has a hardware notch
│   └── ScreenUtils.swift          Finds the notch screen; reads safeAreaInsets.top
│
└── UI/
    ├── NotchWindowController.swift  Owns the borderless NSPanel; hover/click state machine
    ├── NotificationBanner.swift
    ├── Compact/
    │   ├── CompactView.swift       Pill with dual progress bars (session + weekly)
    │   ├── CompactProgressBar.swift
    │   ├── ConstellationView.swift  Multi-provider dot cluster (future use)
    │   └── StatusDot.swift
    ├── Expanded/
    │   ├── ExpandedPanelView.swift  Full hover panel
    │   ├── HeaderRow.swift          Provider name + last-sync time
    │   ├── SessionCard.swift        Animated %, progress bar, time-to-reset
    │   └── WeeklyCard.swift         Rolling weekly quota (providers that expose it)
    ├── Onboarding/
    │   └── OnboardingView.swift     First-launch credential setup
    ├── Settings/
    │   └── SettingsView.swift       Poll interval, notifications, provider management
    └── Theme/
        ├── Theme.swift              Color tokens, typography
        ├── BrandIcon.swift          Provider logos loaded from app bundle
        ├── GlassBackground.swift
        └── RetroMascot.swift
```

---

## Data flow

```
AuthService (Keychain / CLI OAuth)
    │
    ▼
UsageService.start(providers:interval:)
    │  per-provider Task loop + exponential backoff
    │
    ├─ snapshotPublisher ──► UsageCoordinator ──► AppState.snapshots / latestSnapshot
    │                                         └──► NotificationService.evaluate(...)
    │
    └─ errorPublisher ────► UsageCoordinator ──► AppState.providerErrors / authStatus / syncStatus
                                                       │
                                                       ▼
                                              SwiftUI views (CompactView, ExpandedPanelView, etc.)
```

`AppState` is the only `ObservableObject`. All views bind to it directly. No ViewModels.

---

## How the notch window works

`NotchWindowController` creates a borderless, non-activating `NSPanel` at window level `.popUpMenu` (101 — above the macOS menu bar compositor at 24). The panel is anchored at `screen.frame.maxY` (top of screen). Its height is `safeAreaInsets.top` (the hardware notch depth, ~37pt on MBP 14/16") plus the visible content height. The top portion sits inside the physical notch housing — black on black, invisible. Only the lower extension is visible. This is how iOS Dynamic Island works.

Hover detection uses a 40ms `Timer` polling `NSEvent.mouseLocation`. `NSTrackingArea.mouseExited` is unreliable on non-activating panels during resize, and `NSEvent.addGlobalMonitorForEvents` only fires for other apps' events.

---

## Polling and backoff

`UsageService` spawns one `Task` per provider. Fetch errors double the wait interval on each consecutive failure, capped at 1 hour. A 429 response forces at least 5-minute backoff regardless of configured interval. The minimum configurable interval is 60s; the default is 300s.

---

## Auth

Claude has two auth paths, tried in order by `ClaudeProvider`:

1. **CLI OAuth** — reads the `Claude Code-credentials` Keychain item (written by the Claude CLI) or `~/.claude/credentials.json`. No user action needed if `claude` CLI is installed and logged in.
2. **Session cookie** — paste the `Cookie` header from a claude.ai browser session. Stored in the macOS Keychain under `com.claudeusagenotch.ClaudeUsageNotch`.

`AuthService.claudeHasOAuthAvailable` / `cliOAuthAvailable(for:)` check path 1. The onboarding flow adapts to skip the cookie step when CLI OAuth is found.

---

## Adding a provider

1. Add a case to `ProviderId` in `Core/Domain/ProviderId.swift`. Set `isAvailable: Bool`, `usesCLIOAuth: Bool`, and `statusPageBaseURL`.
2. Create a folder under `Providers/YourProvider/` and implement `UsageProvider`:
   - `validateCredentials() async throws` — throw `.unauthorized` on a bad token.
   - `fetchUsage() async throws -> ServiceUsageSnapshot` — map to domain types; never return raw DTOs.
   - Use `ServiceUsageSnapshot.connected(...)` for providers with no quota endpoint, `.balance(...)` for credit-balance providers.
3. Register it in `ProviderRegistry.bootstrap()`.
4. Add credential handling in `AuthService` (Keychain path) or `ClaudeOAuthCredential`-style (CLI file path).
5. Add the source file to the `swiftc` invocation in `scripts/build.sh`.

The UI adapts automatically: `AppState.activeShowsPercentBar`, `activeIsBalance`, and `activeIsStatusOnly` gate which compact and expanded sub-views render.

---

## State persistence

`AppState` persists to `UserDefaults` under the `claudeusagenotch.*` key namespace (see `AppState.Key`). Persisted fields: `activeProvider`, `enabledProviders`, `pollIntervalSeconds`, `notificationsEnabled`, `thresholds`.

Snapshots are not persisted — the app fetches fresh on launch.

---

## Known constraints

- Only Claude is implemented. `ProviderId` is `CaseIterable` with one case; `ProviderRegistry.bootstrap()` registers only `ClaudeProvider`.
- The app is unsigned in Mode A builds. Distributing a Mode A binary produces "app is damaged" errors on other machines. Use Mode B + `sign_and_notarize.sh` for distribution.
- `IncidentMonitor` polls Anthropic's status page; the response shape may change without notice.
- Claude's usage endpoints are undocumented and may break on API changes.

---

## License

MIT
