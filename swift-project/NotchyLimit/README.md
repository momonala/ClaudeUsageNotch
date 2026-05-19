# Notchy Limit

> Your MacBook notch, now showing your AI usage limits.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 12+](https://img.shields.io/badge/macOS-12.0%2B-blue)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)

Notchy Limit is a free, open-source macOS utility that turns your MacBook's hardware notch into a live Claude usage monitor. A minimal pill blends seamlessly with the notch. Hover to expand into a full panel showing session %, weekly quota, time until reset, and threshold alerts — all running locally with zero telemetry.

---

## Features

- **Dynamic Island-style pill** — blends with the hardware notch, shows session % + status glow
- **Mood-reactive mascot** — calm at 0–74%, worried at 75–89%, alarmed at 90%+
- **Arc progress ring** — circular indicator with colour-matched glow keyed to health status
- **Hover to expand / click to pin** — full panel drops down; click anywhere outside to dismiss
- **Hero layout** — giant usage %, reset countdown, rolling counter animation on open
- **Session + weekly cards** — primary (5-hour) and secondary (7-day) usage windows
- **In-app notifications** — banners at 25/50/75/90% (no system permission required)
- **Right-click context menu** — Refresh, Settings, Test notification, Quit without expanding
- **5-minute auto-refresh** with exponential backoff on errors
- **Credentials in Keychain** — cookie never touches UserDefaults or disk
- **Local-first** — talks only to `claude.ai`, zero telemetry
- **Provider-extensible** — clean `UsageProvider` protocol, Gemini stub included
- **MIT licensed** — build it, fork it, audit it

---

## Requirements

| | Minimum |
|---|---|
| macOS | 12.0 Monterey |
| Chip | Apple Silicon (arm64) |
| Xcode CLT | Any version with Swift 5.9+ |
| Xcode (full) | Optional — only for Mode B build |

> **Intel Mac:** Change `-target arm64-apple-macosx12.0` to `-target x86_64-apple-macosx12.0` in `scripts/build.sh`.

---

## Install

### Option A — Build from source (no Xcode required)

```bash
# 1. Install Xcode Command Line Tools (one-time)
xcode-select --install

# 2. Clone
git clone https://github.com/I-N-SILVA/NOTCHY.git
cd NOTCHY/swift-project/NotchyLimit

# 3. Build
bash scripts/build.sh

# 4. Run
open build/NotchyLimit.app
```

The script compiles with `swiftc`, assembles the `.app` bundle, generates the `.icns` icon from included PNGs, and strips the quarantine attribute. No full Xcode install, no code signing, no Apple developer account required.

### Option B — With Xcode (for development)

```bash
brew install xcodegen
cd NOTCHY/swift-project/NotchyLimit
xcodegen generate
open NotchyLimit.xcodeproj   # then ⌘R
```

---

## First launch — getting your Claude cookie

Notchy Limit reads Claude's internal usage endpoint using your session cookie.

1. Open [claude.ai](https://claude.ai) and log in
2. Open DevTools (`⌘ + ⌥ + I`) → **Network** tab
3. Refresh the page and find a request to `usage`
4. Under **Request Headers**, copy the entire `Cookie` value
5. Paste it into Notchy Limit's onboarding screen → **Validate**

The cookie is stored in the macOS **Keychain** — never on disk, never logged to console.

> **Note:** This uses an undocumented Claude endpoint that may change. If it breaks, open an [Issue](https://github.com/I-N-SILVA/NOTCHY/issues).

---

## Usage

| Action | Result |
|---|---|
| Hover over the notch pill | Expands to full panel |
| Click the pill | Pins panel open |
| Click outside the panel | Collapses to pill |
| Press Escape | Collapses to pill |
| Right-click the pill | Context menu: Refresh · Settings · Quit |

---

## Architecture

```
Sources/
├── App/                   @main entry + AppDelegate
├── Core/
│   ├── Domain/            ProviderId · UsageWindow · ServiceUsageSnapshot · Status
│   └── State/             AppState · NotchState
├── Providers/
│   ├── UsageProvider.swift   Protocol + ProviderRegistry
│   ├── Claude/            ClaudeProvider · ClaudeCredential · Endpoint · DTOs
│   └── Gemini/            Stub (coming soon)
├── Services/              UsageService · NotificationService · AuthService
├── Platform/              KeychainStore · ScreenUtils · NotchDetector
└── UI/
    ├── NotchWindowController  NSPanel · hover timer · click-outside monitor
    ├── Compact/           Pill view
    ├── Expanded/          Full panel (session card, weekly card, actions)
    ├── Onboarding/        5-step setup with live pill preview
    ├── Settings/          Notifications · launch at login · providers
    ├── Diagnostics/       Sync status · raw errors
    └── Theme/             Tokens · GlassBackground · NotchPillShape
                           RetroMascot · StatusRingView
```

### How the notch blend works

The panel anchors at `screen.frame.maxY` with height = `safeAreaInsets.top` (hardware notch, ~37 pt) + visible content height. The top portion sits inside the physical camera housing — black blends with hardware. Only the lower portion is visible, identical to iOS Dynamic Island.

### Hover detection

`NSTrackingArea.mouseExited` is unreliable during resize animations. `addGlobalMonitorForEvents` only fires for other apps. The solution: a 40 ms `Timer` polling `NSEvent.mouseLocation` vs `panel.frame` — works at any window level, any activation state.

---

## Adding a provider

1. Create `Sources/Providers/YourProvider/YourProvider.swift`
2. Conform to `UsageProvider`:

```swift
public protocol UsageProvider {
    var id: ProviderId { get }
    var isAvailable: Bool { get }
    func validateCredentials() async throws
    func fetchUsage() async throws -> ServiceUsageSnapshot
}
```

3. Register in `ProviderRegistry.bootstrap()`
4. Add credential handling in `AuthService` if needed

The notch UI, polling loop, and notification system all consume `ServiceUsageSnapshot` — nothing else needs changing.

---

## Privacy

- Cookie stored in macOS **Keychain** — never in UserDefaults, never logged
- No telemetry, no analytics, no remote servers
- Network calls go only to `claude.ai` (and whichever providers you configure)
- MIT licensed — read every line yourself

---

## Contributing

PRs welcome. Good first issues:

- **Gemini provider** — stub is in place, needs a real implementation
- **ChatGPT provider** — OpenAI usage API integration
- **Intel build** — verify and document x86_64 target
- **Sparkle auto-update** — add `Sparkle.framework` update checking
- **Cookie helper** — browser extension to auto-grab the cookie

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Disclaimer

This app uses an **undocumented** Claude endpoint. It is not affiliated with or endorsed by Anthropic. The endpoint may change without notice. Use at your own risk.

---

## License

[MIT](LICENSE)

---

_Built by [Ian Silva](https://github.com/I-N-SILVA)_
