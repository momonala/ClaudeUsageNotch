# Adding a Provider

Notchy Limit is provider-agnostic. Claude is just the first implementation of
the `UsageProvider` protocol. Adding Gemini / ChatGPT / Cursor / etc. is
entirely additive.

## The protocol

```swift
protocol UsageProvider {
    var id: ProviderId { get }
    var displayName: String { get }
    var requiresCookie: Bool { get }
    func validateCredentials() async throws
    func fetchUsage() async throws -> ServiceUsageSnapshot
}
```

Everything else (polling, notifications, UI rendering) consumes
`ServiceUsageSnapshot`s and doesn't care which provider produced them.

## Step-by-step

1. **Create a folder** `Sources/Providers/<Name>/` with at minimum:
   - `<Name>Provider.swift` — conforms to `UsageProvider`.
   - `<Name>Credential.swift` — model for stored credential material.
   - `<Name>Endpoint.swift` — URL + headers.
   - `<Name>UsageDTO.swift` — raw response decoding.
2. **Map the response** into `ServiceUsageSnapshot` (session + weekly windows).
3. **Add an onboarding screen** describing how to obtain the credential.
4. **Register the provider** in `ProviderRegistry.bootstrap()`.
5. **Add it to the provider list** in `Settings → Providers`.

That's it. The notch pill, expanded panel, polling, and notifications will
pick it up automatically.

## Tips

- Treat third-party endpoints as **internal & subject to change**. Wrap
  schema parsing in `do/catch` and surface clear errors to Diagnostics.
- Never log the credential. Use `KeychainStore` for storage.
- Respect rate limits. Default polling is 5 min; expose an override only with
  guard rails.
