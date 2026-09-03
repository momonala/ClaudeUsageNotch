# ClaudeUsageNotch

A native macOS app that displays Claude Code usage (session + weekly quota) live in the hardware notch.

The notch panel works like iOS Dynamic Island: the top portion sits inside the physical camera housing (black on black), and only the visible extension below is rendered. Hover to expand; click to pin open.

---

## Build

For local iteration, `./build.sh` from the repo root kills any running instance, builds
a signed binary (Mode A), and relaunches the app. It resolves the signing identity in
this order:

1. `SIGN_IDENTITY` from the environment, if set — always wins.
2. The first entry of `CANDIDATE_IDENTITIES` present in the keychain: the maintainer's
   Apple Development cert, then `ClaudeUsageNotch Local Signing` (see below).
3. Ad-hoc, with a warning.

Ad-hoc is a last resort, not a neutral default. Its signature is derived from the binary
itself, so every rebuild is a different app to macOS and the Keychain re-prompts for the
Claude Code credentials each time. Any stable identity fixes that — it does not have to
be an Apple one.

**Giving a new machine a stable identity** (no Xcode, no Apple ID, no yearly expiry).
Either use Keychain Access → Certificate Assistant → Create a Certificate… (Self Signed
Root, Code Signing, override the defaults to extend the 365-day validity), or from the
shell:

```bash
cat > cert.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = v3_codesign
prompt             = no
[ dn ]
CN = ClaudeUsageNotch Local Signing
[ v3_codesign ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -config cert.cnf

# -macalg/-keypbe/-certpbe: Security.framework cannot verify the MAC OpenSSL 3
# writes by default, and the import fails with "MAC verification failed".
openssl pkcs12 -export -out bundle.p12 -inkey key.pem -in cert.pem \
  -name "ClaudeUsageNotch Local Signing" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -passout pass:transient

security import bundle.p12 -k ~/Library/Keychains/login.keychain-db \
  -P transient -T /usr/bin/codesign -T /usr/bin/security

# Without this the identity imports but stays CSSMERR_TP_NOT_TRUSTED, and
# `find-identity -v` reports 0 valid identities.
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db cert.pem

rm -f key.pem bundle.p12          # the private key lives in the keychain now
security find-identity -v -p codesigning
```

Confirm a build is stable with `codesign -d -r-`: the designated requirement should read
`identifier "…" and certificate leaf = H"…"`, and be byte-identical across two rebuilds.
The first launch after switching identities prompts once for Keychain access — choose
**Always Allow**, and it stops there.

For a from-scratch build or a different signing identity, use the modes below directly.

**Mode A — no Xcode required (default)**

```bash
cd swift-project/ClaudeUsageNotch
bash scripts/build.sh
open build/ClaudeUsageNotch.app
```

Compiles with `swiftc` directly. Produces an ad-hoc signed binary for local use only. Do not distribute Mode A builds.

To sign with a specific certificate (any stable identity will do — an Apple Development
cert, or the self-signed one above):

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

## Tests

**Swift** — an XcodeGen unit-test target, so it runs through `xcodebuild`
(there is no SPM package):

```bash
cd swift-project/ClaudeUsageNotch
xcodegen generate
xcodebuild test -project ClaudeUsageNotch.xcodeproj -scheme ClaudeUsageNotch -destination 'platform=macOS'
```

Two things make this work that are easy to undo by accident:

- `AppDelegate.applicationDidFinishLaunching` returns early when
  `NSClassFromString("XCTestCase") != nil`. The app bundle is its own test host,
  so a normal launch would start a second notch panel, Keychain reads and
  network polling inside the test process.
- The test target sets `INFOPLIST_KEY_NSPrincipalClass: ""`. Xcode's generated
  Info.plist otherwise defaults it to `NSApplication`, XCTestDriver instantiates
  a *second* one, and AppKit traps before any test runs.

Because the host is the app bundle, `UserDefaults.standard` inside a test is the
live app's own preferences. `NotificationService` takes its store by injection
(`init(defaults:)`) so its tests run against a throwaway suite instead of
clobbering real high-water marks.

**Hook** — stdlib only, run under bare `python3`, matching how Claude Code
invokes it:

```bash
python3 -m unittest discover -s agent-status-hook
```

**Server** — from `claude-usage-notch-server/`, `bash test-and-lint.sh`
(pytest + black + ruff).

---

## Requirements

- macOS 26.0+ (arm64; Intel works with target swap above) — `scripts/build.sh`
  passes `-target arm64-apple-macosx26.0`, and `project.yml` matches it
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
│   │   ├── ServiceUsageSnapshot.swift  One poll's session / weekly / sonnet / credit windows
│   │   ├── UsageRecord.swift      Token-level record parsed from JSONL history
│   │   ├── UsageWindow.swift      One quota window: pace, status, reset helpers
│   │   ├── Timestamps.swift       The two ISO8601 shapes every wire format here uses
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
│       ├── ClaudeCredential.swift  The keychain-stored session cookie
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
    │   ├── CompactView.swift        Session/weekly/credit bars; countdown at session limit
    │   ├── CompactProgressBar.swift Pace marker tick
    │   ├── StatusBubble.swift       Inline outage / sync pill
    │   └── AgentStatusGlow.swift    Perimeter pulse for agent status (compact-idle only)
    ├── Expanded/
    │   ├── ExpandedPanelView.swift  Switches on ExpandedMode
    │   ├── ExpandedPanelGeometry.swift  Panel width/height per mode; shared with NotchWindowController
    │   ├── HeaderRow.swift          Pin badge, mode buttons, hide, quit
    │   ├── UsageCard.swift          One quota window: title, reset info, bar, percentage
    │   ├── ResetHeaderLabel.swift   Countdown · reset time/date · expected usage
    │   ├── UsageChartView.swift     Analytics view: pickers, charts, axes, data loading
    │   ├── QuotaSeries.swift        Token buckets → "% quota over time" (polled or reconstructed)
    │   ├── AnalyticsBreakdowns.swift Cost pills and the right column's ranked breakdowns
    │   └── InlineSettingsView.swift Grouped-form settings pane rendered inline in the notch panel
    ├── Onboarding/OnboardingView.swift
    └── Theme/                       Theme · NotchToggleStyles · NotchPillShape · RetroMascot
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
    └─ errorPublisher ────► UsageCoordinator ──► AppState.authStatus / syncStatus
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

`NotchWindowController` creates a borderless, non-activating `NSPanel` at window level `.popUpMenu` (101 — above the macOS menu bar compositor). The panel anchors at `screen.frame.maxY`. Its height is `safeAreaInsets.top` (the hardware notch height — 32 pt on a 14" M5, but read it per-screen, it varies by model) plus the visible content height.

**Compact width.** The pill is exactly as wide as the physical cutout, in every
state. `ScreenUtils.notchWidth` is the gap between the menu bar's two auxiliary
areas (`screen.frame.width - auxiliaryTopLeftArea.width -
auxiliaryTopRightArea.width`), taken raw — macOS documents those areas as
abutting the camera housing, so the gap *is* the cutout.

Two corrections that used to sit on top of that number are gone, both for the
same reason: they were tuned against one machine and wrong on the next.

- A `max()` floor against `compactPanelWidthDefault` (176 pt), which overshot
  the cutout on any Mac whose notch is narrower than it.
- A fixed 4 pt-per-side `notchFilletInset`, meant to pull the pill's edges in
  off the cutout's filleted corners. It left the pill 8 pt narrow on a 14" MBP,
  which reports a 185 pt gap. The fillets are a question of what shape the pill
  draws, not how wide it is.

Don't expect the two auxiliary areas to be symmetric: a 14" MBP reports 665 pt
left and 662 pt right of a physically centred cutout. That ~3 pt of layout slop
is the accuracy ceiling here, which is the other reason not to hand-tune
point-level corrections on top of it. `compactPanelWidthDefault` survives only
as the fallback for screens with no cutout at all.

**Panel vs. pill.** The compact *panel* is wider than the pill: it carries
`AgentStatusGlow.outset` points of transparent margin on its sides and bottom,
and the pill sits centred inside it. That margin exists so the agent-status ring
can be drawn *outside* the black rather than centred on its edge — a centred
stroke spends its inner half covering the outermost points of the cutout, which
is what made pill-plus-ring measure one cutout wide while the black alone read
narrow. Each stroke is pushed `lineWidth / 2` outward, so its inner edge lands
flush on the fill and its full weight adds to the silhouette. The margin is
reserved whether or not the ring is showing, so the window doesn't resize every
time an agent starts or stops working.

**At the session limit** the pill swaps the `%` readout for a reset countdown —
in the same label slot, so the silhouette doesn't move.
`UsageWindow.timeToReset(.compact)` keeps it to three characters (`45m`, `2h`,
`1d`, floored: `2h` means at least two hours) so it fits the 25 pt slot. The
roomier `.short` width (`2h 58m` — 33 pt of text at 9 pt bold) would not, and
widening the panel to fit it sticks the pill out past the black housing.

**What the pill shows depends on which app you're in.** `FrontmostAppService`
watches `NSWorkspace.frontmostApplication` and publishes whether it's an app a
Claude Code session runs in — a terminal, an editor with one embedded, or the
Claude desktop app, matched by bundle-ID prefix so build variants (VS Code
Insiders, Cursor's per-build ToDesktop identifiers) come along for free.

| Frontmost | Compact panel |
| --- | --- |
| a Claude Code host | the full strip: bars, percentages, reset countdown |
| anything else | the cutout alone — black invisible behind the housing, nothing but the status ring |

Hover expands the full panel from either state; this only governs what the
*collapsed* pill draws. Two details matter. The service ignores activations of
this app itself, since the settings pane takes key focus and that isn't the
user leaving their terminal. And it observes the property by KVO with
`.initial` rather than listening for `didActivateApplicationNotification`: that
notification only fires on a change, so a first reading taken during launch —
while `open` is briefly activating things — would stick until the user next
switched apps, leaving the pill collapsed with the terminal plainly in front.

**Hover detection** uses a 40 ms `Timer` polling `NSEvent.mouseLocation` — `NSTrackingArea` and global event monitors are unreliable on non-activating panels.

The hit region is asymmetric by state (`NotchWindowController.hoverHitRect`):

| State | Region |
| --- | --- |
| compact, notched screen | the cutout itself: top `safeAreaInsets.top` of the panel frame, inset 20 pt per side *from the pill's edges* (i.e. 20 pt + the ring margin from the panel's) |
| compact, no cutout | full panel frame, inset 20 pt per side and 5 pt off the bottom, both measured from the pill |
| expanded | panel frame grown 4 pt on all sides |

Compact is tight on purpose: **you expand by covering the notch, not by
touching the strip.** The strip carrying the bars hangs below the menu bar over
ordinary window content, so treating it as a hover target expanded the panel
whenever the pointer merely travelled up to a window's title bar. The cutout is
unambiguous — nothing else lives there. Screens with no cutout have nothing to
aim at, so they fall back to the strip.

The two regions can't oscillate: collapsing requires leaving the whole expanded
frame, which is far larger than the cutout band inside it.

Expanded stays forgiving — the pointer is already inside the card and a hairline
miss along its edge would collapse it mid-interaction.

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
stable code signature** — `./build.sh` picks one up automatically when the keychain has
one (see [Build](#build)); an ad-hoc build re-prompts after every rebuild.
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

**Drawing.** The stroke wraps the pill from *outside* — see "Panel vs. pill"
above — so it adds to the silhouette rather than covering the outermost points
of black. Three looks, one weight (`ringLineWidth`, except the amber's breath):

| State | Look |
| --- | --- |
| working | faint cyan ring with a comet running along it: a fifth of the perimeter, solid through the middle, fading at head and tail |
| needs input | amber ring breathing thicker and thinner (and fading to `amberTroughOpacity` at the bottom of the breath), its inner edge pinned to the fill |
| just completed | flat green ring, no animation |

Two things are less obvious than they look. The comet's fade is built from
nested segments sharing a midpoint rather than from equal slices with
per-slice opacity: slices have to overlap or a seam shows, the overlap
composites to a third alpha, and those bands crawl along the ring as it
travels. And its length is constant along the whole perimeter — the
compress-through-the-turns, stretch-on-the-straights look comes free from
foreshortening, since the same length of path spans far less visual width once
it wraps a 15 pt corner. Modulating length by corner proximity was tried and
reverted: with the head at constant speed, any change in length is absorbed by
the tail, which then lurches forward and falls back twice a lap.

Both animations start from `onAppear` on **their own branch**, not on the view.
A `repeatForever` animation only applies to views present in the transaction
that started it, so starting both from the view's `onAppear` left whichever
branch appeared *later* frozen at its end state — a comet parked at the corner,
an amber ring stuck at the top of a breath it never took. Status changes while
the glow is on screen are routine, so that was the common path.

**Mechanism.** `agent-status-hook/hook.py` (stdlib-only Python) is invoked by
Claude Code hooks and read-modify-writes a small JSON file at
`~/Library/Application Support/ClaudeUsageNotch/agent-status.json`, keyed by
`session_id`. `AgentStatusService` polls that file (~1.5 s), drops entries that
are stale and non-idle (a session that never sent `Stop`/`SessionEnd` — e.g. a
killed terminal — so it can't hold `working`/`needsInput` forever), and
aggregates the rest with `needsInput` > `working` > `idle` priority so a session
waiting on you is never hidden behind one that's merely working.

**What fires amber.** Two independent paths, because Claude Code has no single
"waiting on the user" event:

1. `Notification` — classified by the payload's `notification_type`, not by
   scraping the message text. `permission_prompt`, `worker_permission_prompt`
   and `agent_needs_input` mean something is blocked on you. `idle_prompt` (the
   60 s "Claude is waiting for your input" nudge) does not: it fires on a timer
   regardless of whether anything is pending, so it only ever preserves an
   existing amber, never creates one.
2. `Stop` — a turn that just ends on a question ("Want me to also update the
   README?") produces no `Notification` at all, yet the session is every bit as
   blocked. The `Stop` handler reads the transcript's last assistant message and
   fires amber when its **last non-empty line ends in `?`** (markdown emphasis
   and trailing brackets/quotes are peeled off first), or when the message
   carries the literal marker `[NEEDS-ACTION]`.

Only the final line is tested. A question mark earlier in a long answer is
usually rhetorical or quoted, and matching it would leave the notch amber after
nearly every turn. The `[NEEDS-ACTION]` marker is honoured but optional — it
depends on a global CLAUDE.md instruction that isn't installed on every machine,
which is exactly why the trailing-question heuristic exists.

Tests live in `agent-status-hook/test_hook.py` and run under bare `python3`
(stdlib only, matching how Claude Code invokes the hook):

```bash
python3 -m unittest discover -s agent-status-hook
```

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
