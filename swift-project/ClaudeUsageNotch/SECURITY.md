# Security Policy

## Reporting a Vulnerability

If you believe you've found a security issue in ClaudeUsageNotch, please **do not**
open a public issue. Instead, email the maintainers (see GitHub profile) with:

- Reproduction steps
- Affected version(s)
- Suggested mitigation, if known

We'll acknowledge within 72 hours and aim to ship a patched release within 14 days
for anything that risks exposing user credentials or data.

## Threat Model

ClaudeUsageNotch is a local-only macOS app. It stores a single `claude.ai` cookie in
the macOS Keychain and makes outbound HTTPS calls to `claude.ai` and
`status.claude.com`. It does not run a server, accept inbound traffic, or sync to
any cloud.

The primary risks we care about:

1. **Credential leakage**: cookies must never be written to UserDefaults,
   stdout/stderr, log files, or pasteboard history.
2. **Schema injection**: untrusted JSON from a provider must be parsed safely
   and never `eval`'d.
3. **Update channel hijack**: any future auto-update channel must be HTTPS-only
   and signed.

## Supported Versions

Only the latest minor release receives security fixes.
