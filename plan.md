# NOTCHY LIMIT — Development Plan

## 1) Objectives
- Ship **Swift/SwiftUI macOS notch utility source scaffold** for **NOTCHY LIMIT** (Claude-first, provider-extensible), buildable by the user on macOS via XcodeGen.
- Ship a **polished landing page** (React) as the runnable artifact with interactive notch demo + mascot.
- Provide a **FastAPI backend** to serve the Swift source as a ZIP + collect waitlist + basic stats.
- Keep V1 focused: onboarding cookie → validate → show notch compact/expanded usage → polling → threshold notifications.

## 2) Implementation Steps

### Phase 1 — Core POC (Isolation): Claude usage fetch + parse (web research + local test)
Why: the most failure-prone core is the **community Claude usage endpoint + cookie auth + response parsing**.

**Steps**
1. Web research: confirm current community-known Claude usage endpoint pattern + required headers/cookies (ClaudeUsageBar + recent forks/issues).
2. Write a minimal **Python script** (`/app/backend/scripts/claude_usage_poc.py`) that:
   - Accepts `CLAUDE_COOKIE` + optional `ORG_ID` env.
   - Calls the usage endpoint, prints status, and extracts normalized fields:
     `session_used`, `session_limit`, `session_reset_at`, `weekly_used`, `weekly_limit`, `weekly_reset_at`.
3. Iterate until it works reliably:
   - Handle 401/403 (bad cookie), 429 (rate limit), schema drift.
   - Save a sample successful JSON response into `/docs/samples/claude_usage.json` for Swift parser parity.

**POC user stories**
1. As a developer, I can run a script with my Claude cookie and get session/weekly usage numbers.
2. As a developer, I see clear errors for invalid/expired cookies.
3. As a developer, I can rerun without being rate-limited by using a safe cadence.
4. As a developer, I can store a sample response for future parser updates.
5. As a developer, I can confirm which headers are strictly required.

---

### Phase 2 — V1 App Development (Swift scaffold + landing page + backend in one pass)

#### 2A) Repo + structure (per PRD)
- Create folders: `/app/swift-project/NotchyLimit/` (Swift source), `/app/frontend/` (React), `/app/backend/` (FastAPI), `/docs/`, `/assets/`.
- Add: `LICENSE (MIT)`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`.

#### 2B) Swift project scaffold (source only, XcodeGen)
**Deliverables**
- `project.yml` (XcodeGen) producing a macOS SwiftUI app.
- `scripts/build.sh`, `create_dmg.sh`, `sign_and_notarize.sh` (documented placeholders where mac-only tooling is needed).

**Core architecture implementation (compile-ready by design)**
- Domain + provider abstraction:
  - `ProviderId`, `UsageWindowType`, `UsageWindow`, `ServiceUsageSnapshot`, `AuthStatus`, `SyncStatus`.
  - `UsageProvider` protocol + `ProviderRegistry`.
- Claude provider:
  - `ClaudeCredential` (cookie), `ClaudeEndpoint`, `ClaudeUsageDTO` + parser mapped to the Phase 1 sample.
  - `ClaudeProvider` implements fetch + validation.
- Services:
  - `AuthService` (KeychainStore), `UsageService` (poll + manual refresh), `UsageCoordinator` (state orchestration).
  - `NotificationService` + `NotificationThresholdConfig` with anti-spam window tracking.
- Platform:
  - `KeychainStore`, `ScreenUtils`, `NotchDetector` (v1: assume notch; fallback stub).

**Notch UI + interactions**
- `NotchWindowController` hosting borderless non-activating `NSPanel`.
- SwiftUI views:
  - Compact pill: session % + reset ETA + status dot.
  - Expanded panel: session card (primary), weekly card (secondary), pace/reset row, actions row, footer.
- Interaction model:
  - Hover intent delay (120–180ms) → expand.
  - Click → pin; Esc/outside click → unpin.

**Onboarding + settings**
- Stepper onboarding:
  - Welcome → choose provider (Claude) → cookie instructions → validate → notifications.
- Settings tabs:
  - Providers (update cookie), Notifications (threshold toggles), Advanced (poll cadence, debug).
- Diagnostics view:
  - last sync time, last status code, raw error category, provider versions.

**Theme**
- `Theme.swift`, `GlassBackground.swift`.
- `RetroMascot.swift`: simple SwiftUI Canvas/SVG-like mascot component.

**Phase 2 user stories (Swift app)**
1. As a user, I can paste my Claude cookie in onboarding and validate before the notch UI appears.
2. As a user, I see a compact pill showing session % used + time until reset.
3. As a user, hovering ~150ms expands the panel; moving away collapses unless pinned.
4. As a user, clicking pins/unpins the expanded panel and Esc closes it.
5. As a user, I can manually refresh and see last sync time update.

#### 2C) Landing page (React, runnable)
- Sections: sticky nav, hero with animated notch demo + retro mascot, how-it-works, privacy, providers roadmap + waitlist, setup accordion, OSS links, download section, footer.
- Interactive notch preview component mirroring compact/expanded/pin behavior.
- Download buttons:
  - **Download Source** → `/api/download/source`.
  - **DMG** → `/api/download/dmg` redirect to GitHub Releases placeholder.

**Phase 2 user stories (Landing page)**
1. As a visitor, I understand the value within one screen (hero + notch demo).
2. As a visitor, I can interact with the notch demo (hover expand, click pin).
3. As a visitor, I can download the Swift source ZIP immediately.
4. As a visitor, I can join the Gemini waitlist by submitting my email.
5. As a visitor, I can follow clear cookie setup instructions without confusion.

#### 2D) Backend (FastAPI + Mongo)
- Endpoints:
  - `GET /api/health`
  - `GET /api/stats` → `{downloads, waitlist_count}` (+ optional `stars` placeholder)
  - `POST /api/waitlist` `{email, provider}` with dedupe (unique index)
  - `GET /api/download/source` streams zip of `/app/swift-project/` and increments counter
  - `GET /api/download/dmg` → 302 to GitHub Releases URL (config)
  - `POST /api/feedback` (optional)
- Zip build: on-demand generate cache + ETag.

**Phase 2 user stories (Backend)**
1. As a visitor, clicking Download Source returns a valid ZIP with correct content-type.
2. As a visitor, downloading increments a counter reflected in `/api/stats`.
3. As a visitor, submitting the waitlist form stores my email once (deduped).
4. As a maintainer, I can change the GitHub release URL via env var.
5. As a developer, I can health-check the API quickly.

**End of Phase 2: Testing (1 full pass)**
- Backend: verify waitlist dedupe + zip stream + stats.
- Frontend: verify section rendering + notch interactivity + waitlist submission + download flows.
- Swift: manual static review for compile readiness + match DTO parsing to sample response.

---

### Phase 3 — Hardening + polish
- Improve Swift source quality:
  - Stronger error taxonomy, retry/backoff, stricter DTO decoding, clearer diagnostics.
  - Refine notch positioning + multi-monitor safety.
- Landing page polish:
  - Performance (bundle size), accessibility, SEO/meta for Product Hunt.
- Backend:
  - Rate limiting on waitlist, basic email validation, CORS tightening.

**Phase 3 user stories**
1. As a user, I see a clear diagnostic message when Claude changes their response schema.
2. As a user, polling failures don’t spam notifications and recover automatically.
3. As a visitor, the landing page loads fast and is readable on mobile.
4. As a maintainer, I can update provider roadmap copy without code changes.
5. As a visitor, I can see privacy guarantees in a clear checklist.

**End of Phase 3: Testing (1 full pass)**
- Re-run frontend/backend tests; spot-check Swift source consistency.

---

### Phase 4 — Release readiness (docs + handoff for mac build)
- Add `docs/BUILDING.md` for macOS steps: XcodeGen → build → run.
- Document cookie extraction steps with screenshots.
- Document signing/notarization workflow (user-run).
- Add GitHub issue templates.

**Phase 4 user stories**
1. As a maintainer, I can follow BUILDING.md to compile the app on my Mac.
2. As a maintainer, I can produce a DMG using provided scripts.
3. As a user, I can troubleshoot setup with a clear diagnostics guide.
4. As a contributor, I can add a provider by implementing `UsageProvider`.
5. As a visitor, I can find GitHub/License/Contributing quickly.

## 3) Next Actions
1. Run Phase 1 web research + implement `claude_usage_poc.py` and capture a sample JSON.
2. Bulk-generate Swift scaffold under `/app/swift-project/NotchyLimit/` using the finalized DTO fields from POC.
3. Implement FastAPI endpoints + zip streaming.
4. Build React landing page with notch demo + mascot + download/waitlist wiring.
5. Execute Phase 2 end-to-end tests (frontend + backend) and fix until stable.

## 4) Success Criteria
- **POC:** Python script successfully fetches and normalizes Claude session + weekly usage with real cookie.
- **Backend:** `/api/download/source` reliably serves a ZIP containing the full Swift scaffold; waitlist dedupes.
- **Landing page:** All sections render; notch demo interactions behave as spec; waitlist + downloads work.
- **Swift scaffold:** Source compiles on macOS (user-verified) with XcodeGen; onboarding + notch UI flow is implemented in code; provider architecture is cleanly extensible.
- **V1 UX:** Compact glanceable pill + expanded details + manual refresh + threshold notifications represented in the scaffold with clear state handling.