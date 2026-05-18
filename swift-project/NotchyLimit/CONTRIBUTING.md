# Contributing to Notchy Limit

Thanks for considering a contribution. This project is small, focused, and
intentionally easy to fork.

## Ground rules

- One PR per change. Keep diffs focused.
- Match existing code style (SwiftUI-first, AppKit only where needed).
- Don't introduce remote services or telemetry. Notchy Limit is **local-only**.
- Don't log raw cookies, tokens, or other credential material.

## Setting up

1. Install Xcode (15+) and XcodeGen: `brew install xcodegen`
2. Clone the repo
3. `cd NotchyLimit && xcodegen generate`
4. Open `NotchyLimit.xcodeproj` and run

## Adding a provider

See `docs/PROVIDER_GUIDE.md`. The TL;DR:

1. Create `Sources/Providers/<Name>/<Name>Provider.swift` conforming to `UsageProvider`.
2. Add credential model and endpoint constants.
3. Register the provider in `ProviderRegistry`.
4. Add an onboarding flow describing how to get credentials.

## Reporting issues

Use GitHub Issues. If reporting an endpoint regression (Claude changed the schema),
include:

- macOS version
- App version
- Last-known-good response shape (from `docs/samples/`)
- Output from the in-app Diagnostics panel (with cookies redacted)

## Code of Conduct

Be kind. We follow the spirit of the Contributor Covenant.
