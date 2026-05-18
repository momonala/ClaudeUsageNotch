# Notchy Limit

> A glanceable macOS notch utility that shows your AI usage limits in real-time. Claude today, more providers coming.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS 12+](https://img.shields.io/badge/macOS-12.0%2B-blue)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)

Notchy Limit lives in your MacBook notch. A tiny pill shows your **session usage %** and **time until reset**. Hover to expand into a full panel with session + weekly cards, manual refresh, and threshold notifications.

## Features

- **Compact notch pill** — session % + status dot + reset ETA, always visible
- **Expanded panel** — session (primary) + weekly (secondary), pace indicator, actions
- **Hover-to-expand** with click-to-pin (Esc unpins)
- **5-minute auto-refresh** + manual refresh
- **Threshold notifications** at 25/50/75/90% (anti-spam: once per window)
- **Provider-extensible** — Claude today, Gemini/others next
- **Local-first** — credentials in Keychain, nothing leaves your Mac
- **MIT licensed** — fully open source

## Quick start

```bash
brew install xcodegen
cd NotchyLimit
xcodegen generate
open NotchyLimit.xcodeproj
```

Build & Run in Xcode (⌘R). On first launch you'll be walked through pasting your `claude.ai` cookie.

Or from the command line:

```bash
./scripts/build.sh
open build/NotchyLimit.app
```

Full build instructions: [`docs/BUILDING.md`](docs/BUILDING.md).

## Cookie setup

See [`docs/COOKIE_SETUP.md`](docs/COOKIE_SETUP.md) for the 30-second walk-through, or use the in-app onboarding.

## Architecture

```
Sources/
  App/                  Entry point + AppDelegate
  Core/                 Domain types + app state
    Domain/             ProviderId, UsageWindow, Snapshot, Status
    State/              AppState, NotchState
  Providers/            UsageProvider protocol + implementations
    Claude/             Claude provider (cookie-based)
    Gemini/             Stub for future
  Services/             UsageService, NotificationService, AuthService
  Platform/             Keychain, ScreenUtils, NotchDetector
  UI/
    Compact/            Notch pill
    Expanded/           Full panel (Session + Weekly cards)
    Onboarding/         5-step setup flow
    Settings/           Providers, notifications, advanced
    Diagnostics/        Last sync, raw errors, versions
    Theme/              Glass background, retro mascot, tokens
```

Adding a provider is a matter of conforming to `UsageProvider` and registering it in `ProviderRegistry`. See [`docs/PROVIDER_GUIDE.md`](docs/PROVIDER_GUIDE.md).

## Privacy

- Cookie stored in **macOS Keychain** (never in plain UserDefaults, never logged)
- No telemetry, no analytics, no remote servers in the loop
- The app talks **only** to `claude.ai` (or whichever provider you configure)
- Source is MIT — audit it yourself

## Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the basics.

## Disclaimer

Notchy Limit uses Claude's internal usage endpoint, which is **undocumented** and may change without notice. Not affiliated with Anthropic. Use at your own risk.

## License

MIT — see [`LICENSE`](LICENSE).
