# ClaudeUsageNotch

Two components in one repo:

- `swift-project/ClaudeUsageNotch/` — the macOS notch app (Swift/SwiftUI).
- `claude-usage-notch-server/` — the Python analytics server (Flask + SQLite), a git submodule.

Read `README.md` first for architecture, data flow, and the API contract.

## Build & test

To validate a change, run the relevant tests and then the root build script.

**1. Tests**

Swift unit tests (`Tests/ClaudeUsageNotchTests.swift`) are an XcodeGen
unit-test target — there is no SPM package, so run them through `xcodebuild`
from `swift-project/ClaudeUsageNotch/`:

```bash
xcodegen generate                                   # regenerate ClaudeUsageNotch.xcodeproj
xcodebuild test -project ClaudeUsageNotch.xcodeproj \
  -scheme ClaudeUsageNotch -destination 'platform=macOS'
```

Server tests — from `claude-usage-notch-server/` (use `uv`, never bare `python`):

```bash
bash test-and-lint.sh            # pytest + black + ruff
uv run pytest tests/ -q          # tests only
```

**2. Build & launch**

From the repo root:

```bash
./build.sh
```

It kills any running instance, builds the signed `.app` (via
`swift-project/ClaudeUsageNotch/scripts/build.sh`), and relaunches it so the
change can be verified live. See `README.md` for the underlying build modes
(`SIGN_IDENTITY=…`, `USE_XCODEBUILD=1`).
