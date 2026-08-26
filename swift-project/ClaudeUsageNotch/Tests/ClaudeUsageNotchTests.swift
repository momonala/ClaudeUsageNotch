import XCTest
@testable import ClaudeUsageNotch

// MARK: - ClaudeUsageMapper Tests

final class ClaudeUsageMappingTests: XCTestCase {

    // 1. Happy path: all three windows present.
    func test_snapshot_parsesAllWindows() throws {
        let json = """
        {
          "five_hour":        { "utilization": 42.5, "resets_at": "2026-05-18T10:00:00Z" },
          "seven_day":        { "utilization": 61.0, "resets_at": "2026-05-25T00:00:00Z" },
          "seven_day_sonnet": { "utilization": 28.0, "resets_at": "2026-05-25T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        let snapshot = try ClaudeUsageMapper.snapshot(from: dto)

        XCTAssertEqual(snapshot.sessionWindow.percentUsed, 0.425, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.weeklyWindow).percentUsed, 0.610, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.weeklySonnetWindow).percentUsed, 0.280, accuracy: 0.001)
        XCTAssertNotNil(snapshot.sessionWindow.resetAt)
    }

    // 1b. Team-plan `spend` block maps to a `.monthly` credit window.
    func test_snapshot_parsesCreditWindowFromSpend() throws {
        let json = """
        {
          "five_hour": { "utilization": 3.0, "resets_at": "2026-08-22T08:30:00Z" },
          "spend": {
            "used":  { "amount_minor": 420,   "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 35000, "currency": "USD", "exponent": 2 },
            "percent": 1.2,
            "enabled": true
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        let snapshot = try ClaudeUsageMapper.snapshot(from: dto)

        let credit = try XCTUnwrap(snapshot.creditWindow)
        XCTAssertEqual(credit.type, .monthly)
        XCTAssertEqual(credit.percentUsed, 0.012, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(credit.usedAmount), 4.20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(credit.limitAmount), 350.00, accuracy: 0.001)
        XCTAssertNotNil(credit.resetAt)
    }

    // 1c. `spend.enabled == false` (or the block absent) → no credit window.
    func test_snapshot_omitsCreditWindowWhenSpendDisabled() throws {
        let json = """
        {
          "five_hour": { "utilization": 3.0, "resets_at": "2026-08-22T08:30:00Z" },
          "spend": {
            "used":  { "amount_minor": 0, "currency": "USD", "exponent": 2 },
            "limit": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
            "percent": 0,
            "enabled": false
          }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        let snapshot = try ClaudeUsageMapper.snapshot(from: dto)

        XCTAssertNil(snapshot.creditWindow)
    }

    // 2. Missing five_hour → decoding error.
    func test_snapshot_throwsWhenFiveHourMissing() throws {
        let json = """
        {
          "seven_day": { "utilization": 61.0, "resets_at": "2026-05-25T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        XCTAssertThrowsError(try ClaudeUsageMapper.snapshot(from: dto)) { error in
            guard case ProviderError.decoding = error else {
                return XCTFail("Expected ProviderError.decoding, got \(error)")
            }
        }
    }

    // 3. Null utilization on five_hour → decoding error.
    func test_snapshot_throwsWhenUtilizationNull() throws {
        let json = """
        { "five_hour": { "resets_at": "2026-05-18T10:00:00Z" } }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        XCTAssertThrowsError(try ClaudeUsageMapper.snapshot(from: dto)) { error in
            guard case ProviderError.decoding = error else {
                return XCTFail("Expected ProviderError.decoding, got \(error)")
            }
        }
    }

    // 4. Missing optional windows → weeklyWindow and weeklySonnetWindow are nil.
    func test_snapshot_optionalWindowsAreNil() throws {
        let json = """
        { "five_hour": { "utilization": 10.0, "resets_at": null } }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        let snapshot = try ClaudeUsageMapper.snapshot(from: dto)

        XCTAssertNil(snapshot.weeklyWindow)
        XCTAssertNil(snapshot.weeklySonnetWindow)
        XCTAssertNil(snapshot.sessionWindow.resetAt)
    }
}

// MARK: - Snapshot factory tests

final class SnapshotFactoryTests: XCTestCase {

    func test_connectedSnapshot_isStatusOnly() {
        let snapshot = ServiceUsageSnapshot.connected()
        XCTAssertTrue(snapshot.isStatusOnly)
        XCTAssertFalse(snapshot.showsPercentBar)
        XCTAssertEqual(snapshot.shortLabel, "Active")
    }

    func test_connectedSnapshot_hasNoSecondaryWindows() {
        let snapshot = ServiceUsageSnapshot.connected()
        XCTAssertNil(snapshot.weeklyWindow)
        XCTAssertNil(snapshot.weeklySonnetWindow)
    }
}

// MARK: - ClaudeOAuthCredential Parsing Tests

final class ClaudeOAuthCredentialTests: XCTestCase {

    // 14. Standard claudeAiOauthToken field.
    func test_parse_claudeAiOauthToken_field() {
        let json = #"{"claudeAiOauthToken":"tok-abc123","expiresAt":9999999999999}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertEqual(cred?.accessToken, "tok-abc123")
    }

    // 15. Falls back to accessToken field.
    func test_parse_accessToken_field() {
        let json = #"{"accessToken":"sk-ant-oauth01XYZ"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertEqual(cred?.accessToken, "sk-ant-oauth01XYZ")
    }

    // 16. Falls back to token field.
    func test_parse_token_field() {
        let json = #"{"token":"raw-token-value"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertEqual(cred?.accessToken, "raw-token-value")
    }

    // 17. Empty string token → nil.
    func test_parse_emptyToken_returnsNil() {
        let json = #"{"claudeAiOauthToken":""}"#.data(using: .utf8)!
        XCTAssertNil(ClaudeOAuthCredential.parse(from: json))
    }

    // 18. No token field → nil.
    func test_parse_missingToken_returnsNil() {
        let json = #"{"expiresAt":9999999999999}"#.data(using: .utf8)!
        XCTAssertNil(ClaudeOAuthCredential.parse(from: json))
    }

    // 19. Invalid JSON → nil.
    func test_parse_malformedJSON_returnsNil() {
        XCTAssertNil(ClaudeOAuthCredential.parse(from: Data("not json".utf8)))
    }

    // 20. Expiry as millisecond Unix timestamp (> 1e12).
    func test_parse_expiryMilliseconds() {
        // 9_999_999_999_000 ms = 9_999_999_999 s  (far future)
        let json = #"{"claudeAiOauthToken":"t","expiresAt":9999999999000}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertNotNil(cred?.expiresAt)
        XCTAssertFalse(cred?.isLikelyExpired ?? true)
    }

    // 21. Expiry as second Unix timestamp.
    func test_parse_expirySeconds() {
        let future = Date().timeIntervalSince1970 + 3600
        let json = "{\"claudeAiOauthToken\":\"t\",\"expiresAt\":\(future)}".data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertFalse(cred?.isLikelyExpired ?? true, "Token expires in 1 hour, should not be expired")
    }

    // 22. Expired token → isLikelyExpired is true.
    func test_parse_expiredToken_isLikelyExpired() {
        let past = Date().timeIntervalSince1970 - 3600
        let json = "{\"claudeAiOauthToken\":\"t\",\"expiresAt\":\(past)}".data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertTrue(cred?.isLikelyExpired ?? false)
    }

    // 23. ISO-8601 expiry string.
    func test_parse_expiryISO8601String() {
        let json = #"{"claudeAiOauthToken":"t","expiresAt":"2099-01-01T00:00:00Z"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertNotNil(cred?.expiresAt)
        XCTAssertFalse(cred?.isLikelyExpired ?? true)
    }

    // 24. No expiresAt → expiresAt is nil, isLikelyExpired is false (assume valid).
    func test_parse_noExpiry_notExpired() {
        let json = #"{"claudeAiOauthToken":"t"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertNil(cred?.expiresAt)
        XCTAssertFalse(cred?.isLikelyExpired ?? true)
    }
}

// MARK: - NotificationService high-water mark tests

// `NotificationService` is @MainActor-isolated, so its tests have to be too.
@MainActor
final class NotificationServiceEvaluateTests: XCTestCase {

    private let defaultsKey = "com.claudeusagenotch.NotificationService.highWaterMark"
    private let thresholds: [Double] = [0.25, 0.5, 0.75, 0.9]

    // A throwaway suite and a fresh service per test. Clearing keys in
    // `UserDefaults.standard` isn't enough on two counts: the shared instance
    // caches its marks in memory at init, so a cleared key leaves the previous
    // test's mark in play; and the test host *is* the app bundle, so
    // `.standard` is the live app's own preferences.
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var service: NotificationService!

    override func setUp() {
        super.setUp()
        suiteName = "com.claudeusagenotch.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = NotificationService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        service = nil
        super.tearDown()
    }

    private func snapshot(percent: Double) -> ServiceUsageSnapshot {
        ServiceUsageSnapshot(
            sessionWindow: UsageWindow(type: .session, percentUsed: percent,
                                       lastUpdated: Date()),
            capturedAt: Date()
        )
    }

    private func mark() -> [String: Double] {
        defaults.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    }

    // 5a. Skipping thresholds: jumping from 0% to 76% records the 75% mark.
    func test_skippedThresholds_recordsHighestOnly() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.75,
                       "mark should be 0.75 — the highest crossed threshold")
    }

    // 5b. Repeated polls at the same usage level fire nothing extra.
    func test_repeatedEvaluate_doesNotReFire() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        let markAfterFirst = mark()
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark(), markAfterFirst,
                       "mark must not change on a second evaluate at the same usage")
    }

    // 5c. Crossing a higher threshold on a later poll fires once more.
    func test_newHigher_threshold_fires() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.75)
        service.evaluate(snapshot: snapshot(percent: 0.92), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.9,
                       "mark should advance to 0.9 when usage crosses 90%")
    }

    // 5d. Window reset: usage drops below the lowest threshold → mark clears.
    func test_windowReset_clearsMark() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.75)
        service.evaluate(snapshot: snapshot(percent: 0.05), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0,
                       "mark should clear to 0 when usage drops below lowest threshold")
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.75,
                       "mark should advance again after window reset")
    }

    // 5e. Reset detection works even when all threshold buttons are cleared.
    func test_windowReset_firesWithEmptyThresholds() {
        service.evaluate(snapshot: snapshot(percent: 0.82), thresholds: [])
        service.evaluate(snapshot: snapshot(percent: 0.0), thresholds: [])
        XCTAssertEqual(mark()["claude:session"], 0,
                       "reset should clear threshold mark even with no thresholds configured")
    }

    // 5f. Reset detection: a drop to near-zero is a reset; a rolling-window dip
    // while usage is still high is not.
    func test_windowReset_detectsReset() {
        XCTAssertTrue(NotificationService.didWindowReset(previous: 1.0, current: 0.0))
        XCTAssertTrue(NotificationService.didWindowReset(previous: 0.76, current: 0.05))
        XCTAssertFalse(NotificationService.didWindowReset(previous: 0.5, current: 0.76))
        XCTAssertFalse(NotificationService.didWindowReset(previous: 0.76, current: 0.76))
        // Rolling-window dip — old usage ages out but usage is still high: NOT a reset.
        XCTAssertFalse(NotificationService.didWindowReset(previous: 0.42, current: 0.40))
    }

    // 6. KeychainStore round-trip: write → read → delete.
    func test_keychainStore_roundTrip() {
        let store = KeychainStore(service: "com.claudeusagenotch.tests.\(UUID().uuidString)")
        let payload = "test-payload-\(UUID().uuidString)".data(using: .utf8)!
        store.set(account: "roundtrip", data: payload)
        let read = store.get(account: "roundtrip")
        XCTAssertEqual(read, payload)
        let deleted = store.delete(account: "roundtrip")
        XCTAssertTrue(deleted)
        XCTAssertNil(store.get(account: "roundtrip"))
    }
}

// MARK: - AgentStatus Tests

final class AgentStatusTests: XCTestCase {

    // 1. Aggregation priority: needsInput beats working beats idle.
    func test_aggregate_needsInputWinsOverWorking() {
        XCTAssertEqual(AgentStatus.aggregate([.working, .needsInput, .idle]), .needsInput)
    }

    func test_aggregate_workingWinsOverIdle() {
        XCTAssertEqual(AgentStatus.aggregate([.idle, .working]), .working)
    }

    func test_aggregate_allIdle_isIdle() {
        XCTAssertEqual(AgentStatus.aggregate([.idle, .idle]), .idle)
    }

    func test_aggregate_empty_isIdle() {
        XCTAssertEqual(AgentStatus.aggregate([]), .idle)
    }

    // 2. Status-file decoding round-trips through the same shape the hook writes.
    func test_sessionEntry_decodesHookShape() throws {
        let json = """
        {"status": "working", "event": "PreToolUse", "ts": 1737657600.2, "cwd": "/tmp/project"}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(AgentSessionEntry.self, from: json)
        XCTAssertEqual(entry.status, .working)
        XCTAssertEqual(entry.event, "PreToolUse")
        XCTAssertEqual(entry.cwd, "/tmp/project")
    }

    // 3. A crashed session (no Stop/SessionEnd, stale timestamp) is dropped
    // rather than holding a needs-input/working state forever.
    func test_reading_dropsStaleNonIdleEntry() {
        let now: TimeInterval = 1_000_000
        let stale = AgentSessionEntry(status: .needsInput, event: "Notification", ts: now - 500, cwd: "")
        let reading = AgentStatusReading.from([stale], now: now, staleAfter: 180)
        XCTAssertEqual(reading.status, .idle)
    }

    // 4. A fresh entry within the staleness window still counts.
    func test_reading_keepsFreshEntry() {
        let now: TimeInterval = 1_000_000
        let fresh = AgentSessionEntry(status: .working, event: "PreToolUse", ts: now - 10, cwd: "")
        let reading = AgentStatusReading.from([fresh], now: now, staleAfter: 180)
        XCTAssertEqual(reading.status, .working)
    }

    // 5. A second, needs-input session overrides a first, merely-working session.
    func test_reading_multiSession_needsInputOverridesWorking() {
        let now: TimeInterval = 1_000_000
        let working = AgentSessionEntry(status: .working, event: "PreToolUse", ts: now, cwd: "/a")
        let waiting = AgentSessionEntry(status: .needsInput, event: "Notification", ts: now, cwd: "/b")
        let reading = AgentStatusReading.from([working, waiting], now: now)
        XCTAssertEqual(reading.status, .needsInput)
    }

    // 6. justCompleted flashes briefly after a Stop, then expires.
    func test_reading_justCompleted_withinWindow() {
        let now: TimeInterval = 1_000_000
        let stopped = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 2, cwd: "")
        let reading = AgentStatusReading.from([stopped], now: now, completedWithin: 4)
        XCTAssertTrue(reading.justCompleted)
        XCTAssertEqual(reading.status, .idle)
    }

    func test_reading_justCompleted_expiresAfterWindow() {
        let now: TimeInterval = 1_000_000
        let stopped = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 10, cwd: "")
        let reading = AgentStatusReading.from([stopped], now: now, completedWithin: 4)
        XCTAssertFalse(reading.justCompleted)
    }

    // 7. The completion flash holds for the full default window (30s), so a
    // finished session stays visible long enough to notice.
    func test_reading_justCompleted_defaultWindowHoldsFor30s() {
        let now: TimeInterval = 1_000_000
        let stopped = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 25, cwd: "")
        XCTAssertTrue(AgentStatusReading.from([stopped], now: now).justCompleted)

        let older = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 31, cwd: "")
        XCTAssertFalse(AgentStatusReading.from([older], now: now).justCompleted)
    }

    // 8. A live session outranks another session's completion flash — the green
    // pulse must never mask one that is working or wants input.
    func test_reading_justCompleted_supersededByWorkingSession() {
        let now: TimeInterval = 1_000_000
        let stopped = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 2, cwd: "/done")
        let working = AgentSessionEntry(status: .working, event: "PreToolUse", ts: now, cwd: "/busy")
        let reading = AgentStatusReading.from([stopped, working], now: now)
        XCTAssertEqual(reading.status, .working)
        XCTAssertFalse(reading.justCompleted)
    }

    func test_reading_justCompleted_supersededByNeedsInputSession() {
        let now: TimeInterval = 1_000_000
        let stopped = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 2, cwd: "/done")
        let waiting = AgentSessionEntry(status: .needsInput, event: "Notification", ts: now, cwd: "/ask")
        let reading = AgentStatusReading.from([stopped, waiting], now: now)
        XCTAssertEqual(reading.status, .needsInput)
        XCTAssertFalse(reading.justCompleted)
    }
}

// MARK: - ExpandedPanelGeometry Tests

final class ExpandedPanelGeometryTests: XCTestCase {

    /// The card must always be strictly shorter than the window content it sits
    /// in, or it renders up under the hardware notch — the bug that made the
    /// settings panel look misformatted.
    func test_cardAlwaysFitsInsideWindowContentWithGap() {
        for mode in [ExpandedMode.usage, .analytics, .settings] {
            let card = ExpandedPanelGeometry.cardHeight(for: mode)
            let content = ExpandedPanelGeometry.windowContentHeight(for: mode, hasCredit: false)
            XCTAssertGreaterThan(content, card, "\(mode) card must leave room for the notch gap")
            XCTAssertEqual(content - card, ExpandedPanelGeometry.notchGap(for: mode), accuracy: 0.001)
        }
    }

    func test_creditExtraAppliesToUsageOnly() {
        XCTAssertEqual(
            ExpandedPanelGeometry.windowContentHeight(for: .usage, hasCredit: true)
                - ExpandedPanelGeometry.windowContentHeight(for: .usage, hasCredit: false),
            ExpandedPanelGeometry.usageCreditExtra, accuracy: 0.001
        )
        XCTAssertEqual(
            ExpandedPanelGeometry.windowContentHeight(for: .settings, hasCredit: true),
            ExpandedPanelGeometry.windowContentHeight(for: .settings, hasCredit: false), accuracy: 0.001
        )
    }
}
