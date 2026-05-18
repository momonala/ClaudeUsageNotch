# Getting your Claude session cookie

Notchy Limit reads your Claude usage by calling the same internal endpoint that
`claude.ai`'s own Settings → Usage page calls. To do that it needs your full
browser cookie for `claude.ai`.

**Your cookie never leaves your Mac.** It's stored in the macOS Keychain and
used only to call `https://claude.ai/api/...`.

## Steps (30 seconds)

1. Open **[claude.ai/settings/usage](https://claude.ai/settings/usage)** in your
   browser and make sure you're logged in.
2. Open DevTools: ⌘+⌥+I (Chrome/Brave/Edge/Arc) or ⌘+⌥+I (Safari, after enabling
   the Develop menu).
3. Switch to the **Network** tab.
4. Refresh the page (⌘R).
5. Find the request named **`usage`** in the list.
6. Scroll to **Request Headers** and copy the **full `Cookie`** value.
7. Paste it into Notchy Limit's onboarding step "Paste cookie".

The cookie starts with something like `anthropic-device-id=...` and is long.

## What can go wrong

- **"Invalid or expired cookie"** — try logging out and back in on claude.ai,
  then re-copy.
- **"Could not find org id"** — the cookie should contain `lastActiveOrg=...`.
  If it doesn't, Notchy Limit falls back to `/api/bootstrap` to discover it.
- **The page doesn't refresh requests** — hard reload with ⌘+⇧+R.

## Why a cookie?

There's no public Claude API for usage data. The cookie auths you to Claude's
internal endpoint, which is the same path the official UI uses. We do exactly
the same call your browser does.
