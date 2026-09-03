import XCTest
import AppKit
@testable import ClaudeUsageNotch

// MARK: - ClaudeUsageMapper

final class ClaudeUsageMappingTests: XCTestCase {

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

// MARK: - ClaudeOAuthCredential parsing

final class ClaudeOAuthCredentialTests: XCTestCase {

    func test_parse_claudeAiOauthToken_field() {
        let json = #"{"claudeAiOauthToken":"tok-abc123","expiresAt":9999999999999}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertEqual(cred?.accessToken, "tok-abc123")
    }

    func test_parse_accessToken_field() {
        let json = #"{"accessToken":"sk-ant-oauth01XYZ"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertEqual(cred?.accessToken, "sk-ant-oauth01XYZ")
    }

    func test_parse_token_field() {
        let json = #"{"token":"raw-token-value"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertEqual(cred?.accessToken, "raw-token-value")
    }

    func test_parse_emptyToken_returnsNil() {
        let json = #"{"claudeAiOauthToken":""}"#.data(using: .utf8)!
        XCTAssertNil(ClaudeOAuthCredential.parse(from: json))
    }

    func test_parse_missingToken_returnsNil() {
        let json = #"{"expiresAt":9999999999999}"#.data(using: .utf8)!
        XCTAssertNil(ClaudeOAuthCredential.parse(from: json))
    }

    func test_parse_malformedJSON_returnsNil() {
        XCTAssertNil(ClaudeOAuthCredential.parse(from: Data("not json".utf8)))
    }

    func test_parse_expiryMilliseconds() {
        // 9_999_999_999_000 ms = 9_999_999_999 s  (far future)
        let json = #"{"claudeAiOauthToken":"t","expiresAt":9999999999000}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertNotNil(cred?.expiresAt)
        XCTAssertFalse(cred?.isLikelyExpired ?? true)
    }

    func test_parse_expirySeconds() {
        let future = Date().timeIntervalSince1970 + 3600
        let json = "{\"claudeAiOauthToken\":\"t\",\"expiresAt\":\(future)}".data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertFalse(cred?.isLikelyExpired ?? true, "Token expires in 1 hour, should not be expired")
    }

    func test_parse_expiredToken_isLikelyExpired() {
        let past = Date().timeIntervalSince1970 - 3600
        let json = "{\"claudeAiOauthToken\":\"t\",\"expiresAt\":\(past)}".data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertTrue(cred?.isLikelyExpired ?? false)
    }

    func test_parse_expiryISO8601String() {
        let json = #"{"claudeAiOauthToken":"t","expiresAt":"2099-01-01T00:00:00Z"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertNotNil(cred?.expiresAt)
        XCTAssertFalse(cred?.isLikelyExpired ?? true)
    }

    func test_parse_noExpiry_notExpired() {
        let json = #"{"claudeAiOauthToken":"t"}"#.data(using: .utf8)!
        let cred = ClaudeOAuthCredential.parse(from: json)
        XCTAssertNil(cred?.expiresAt)
        XCTAssertFalse(cred?.isLikelyExpired ?? true)
    }
}

// MARK: - NotificationService high-water marks

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

    func test_skippedThresholds_recordsHighestOnly() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.75,
                       "mark should be 0.75 — the highest crossed threshold")
    }

    func test_repeatedEvaluate_doesNotReFire() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        let markAfterFirst = mark()
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark(), markAfterFirst,
                       "mark must not change on a second evaluate at the same usage")
    }

    func test_newHigher_threshold_fires() {
        service.evaluate(snapshot: snapshot(percent: 0.76), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.75)
        service.evaluate(snapshot: snapshot(percent: 0.92), thresholds: thresholds)
        XCTAssertEqual(mark()["claude:session"], 0.9,
                       "mark should advance to 0.9 when usage crosses 90%")
    }

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

    func test_windowReset_firesWithEmptyThresholds() {
        service.evaluate(snapshot: snapshot(percent: 0.82), thresholds: [])
        service.evaluate(snapshot: snapshot(percent: 0.0), thresholds: [])
        XCTAssertEqual(mark()["claude:session"], 0,
                       "reset should clear threshold mark even with no thresholds configured")
    }

    func test_windowReset_detectsReset() {
        XCTAssertTrue(NotificationService.didWindowReset(previous: 1.0, current: 0.0))
        XCTAssertTrue(NotificationService.didWindowReset(previous: 0.76, current: 0.05))
        XCTAssertFalse(NotificationService.didWindowReset(previous: 0.5, current: 0.76))
        XCTAssertFalse(NotificationService.didWindowReset(previous: 0.76, current: 0.76))
        // Rolling-window dip — old usage ages out but usage is still high: NOT a reset.
        XCTAssertFalse(NotificationService.didWindowReset(previous: 0.42, current: 0.40))
    }

}

// MARK: - KeychainStore

final class KeychainStoreTests: XCTestCase {

    func test_roundTrip_writeReadDelete() {
        let store = KeychainStore(service: "com.claudeusagenotch.tests.\(UUID().uuidString)")
        let payload = "test-payload-\(UUID().uuidString)".data(using: .utf8)!
        store.set(account: "roundtrip", data: payload)
        XCTAssertEqual(store.get(account: "roundtrip"), payload)
        XCTAssertTrue(store.delete(account: "roundtrip"))
        XCTAssertNil(store.get(account: "roundtrip"))
    }
}

// MARK: - AgentStatus

final class AgentStatusTests: XCTestCase {

    func test_aggregate_needsInputWinsOverWorking() {
        XCTAssertEqual(AgentStatus.aggregate([.working, .needsInput, .idle]), .needsInput)
    }

    func test_aggregate_workingWinsOverIdle() {
        XCTAssertEqual(AgentStatus.aggregate([.idle, .working]), .working)
    }

    func test_aggregate_nothingActive_isIdle() {
        XCTAssertEqual(AgentStatus.aggregate([.idle, .idle]), .idle)
        XCTAssertEqual(AgentStatus.aggregate([]), .idle)
    }

    func test_sessionEntry_decodesHookShape() throws {
        let json = """
        {"status": "working", "event": "PreToolUse", "ts": 1737657600.2, "cwd": "/tmp/project"}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(AgentSessionEntry.self, from: json)
        XCTAssertEqual(entry.status, .working)
        XCTAssertEqual(entry.event, "PreToolUse")
        XCTAssertEqual(entry.cwd, "/tmp/project")
    }

    func test_reading_dropsStaleNonIdleEntry() {
        let now: TimeInterval = 1_000_000
        let stale = AgentSessionEntry(status: .needsInput, event: "Notification", ts: now - 500, cwd: "")
        let reading = AgentStatusReading.from([stale], now: now, staleAfter: 180)
        XCTAssertEqual(reading.status, .idle)
    }

    func test_reading_keepsFreshEntry() {
        let now: TimeInterval = 1_000_000
        let fresh = AgentSessionEntry(status: .working, event: "PreToolUse", ts: now - 10, cwd: "")
        let reading = AgentStatusReading.from([fresh], now: now, staleAfter: 180)
        XCTAssertEqual(reading.status, .working)
    }

    func test_reading_multiSession_needsInputOverridesWorking() {
        let now: TimeInterval = 1_000_000
        let working = AgentSessionEntry(status: .working, event: "PreToolUse", ts: now, cwd: "/a")
        let waiting = AgentSessionEntry(status: .needsInput, event: "Notification", ts: now, cwd: "/b")
        let reading = AgentStatusReading.from([working, waiting], now: now)
        XCTAssertEqual(reading.status, .needsInput)
    }

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

    func test_reading_justCompleted_defaultWindowHoldsFor30s() {
        let now: TimeInterval = 1_000_000
        let stopped = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 25, cwd: "")
        XCTAssertTrue(AgentStatusReading.from([stopped], now: now).justCompleted)

        let older = AgentSessionEntry(status: .idle, event: "Stop", ts: now - 31, cwd: "")
        XCTAssertFalse(AgentStatusReading.from([older], now: now).justCompleted)
    }

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

// MARK: - ExpandedPanelGeometry

final class ExpandedPanelGeometryTests: XCTestCase {

    /// The card must be strictly shorter than the window content it sits in, or
    /// it renders up under the hardware notch.
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

// MARK: - Compact reset countdown

final class CompactCountdownTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func sessionWindow(resettingIn seconds: TimeInterval) -> UsageWindow {
        UsageWindow(
            type: .session,
            percentUsed: 1.0,
            resetAt: now.addingTimeInterval(seconds),
            lastUpdated: now
        )
    }

    func test_compactString_keepsOnlyTheLargestUnit() {
        XCTAssertEqual(sessionWindow(resettingIn: 45 * 60).timeToReset(.compact, now: now), "45m")
        XCTAssertEqual(sessionWindow(resettingIn: 3600).timeToReset(.compact, now: now), "1h")
        XCTAssertEqual(sessionWindow(resettingIn: 2 * 3600 + 58 * 60).timeToReset(.compact, now: now), "2h")
        XCTAssertEqual(sessionWindow(resettingIn: 25 * 3600).timeToReset(.compact, now: now), "1d")
    }

    func test_compactString_floorsRatherThanRounds() {
        // "2h" has to mean *at least* two hours, never "nearly three".
        XCTAssertEqual(sessionWindow(resettingIn: 2 * 3600 + 59 * 60 + 59).timeToReset(.compact, now: now), "2h")
    }

    func test_compactString_neverReportsZero() {
        XCTAssertEqual(sessionWindow(resettingIn: 30).timeToReset(.compact, now: now), "1m")
        XCTAssertEqual(sessionWindow(resettingIn: 0).timeToReset(.compact, now: now), "now")
        XCTAssertEqual(sessionWindow(resettingIn: -60).timeToReset(.compact, now: now), "now")
    }

    func test_compactString_isNilWithoutResetAt() {
        let window = UsageWindow(type: .session, percentUsed: 1.0, resetAt: nil, lastUpdated: now)
        XCTAssertNil(window.timeToReset(.compact, now: now))
    }

    /// The whole point of the compact form: at the session limit the pill shows
    /// this string in the same slot the "%" readout uses, so it has to fit —
    /// otherwise the pill clips or grows wider than the hardware cutout.
    func test_compactString_fitsThePercentLabelSlot() {
        let slotWidth: CGFloat = 25
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        let intervals: [TimeInterval] = [0, 30, 59 * 60, 3600, 5 * 3600, 23 * 3600, 25 * 3600, 9 * 24 * 3600]
        for interval in intervals {
            let text = try! XCTUnwrap(sessionWindow(resettingIn: interval).timeToReset(.compact, now: now))
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, slotWidth, "\"\(text)\" overflows the \(slotWidth) pt label slot")
        }
        // The fallback shown when the window has no reset time has to fit too.
        let fallbackWidth = ("MAX" as NSString).size(withAttributes: [.font: font]).width
        XCTAssertLessThanOrEqual(fallbackWidth, slotWidth)
    }

    /// The pill is the hardware cutout, in every state. Nothing about the
    /// session's usage may feed into its width.
    func test_compactPanelWidth_isTheNotchWidthRegardlessOfState() {
        XCTAssertEqual(ScreenUtils.compactPanelWidthBase, ScreenUtils.notchWidth, accuracy: 0.001)
    }
}

// MARK: - Which app the pill shows its readout in

final class FrontmostAppTests: XCTestCase {

    func test_terminalsAndEditorsCountAsWorkHosts() {
        for id in ["com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty",
                   "io.alacritty", "dev.warp.Warp", "com.microsoft.VSCode"] {
            XCTAssertTrue(FrontmostAppService.isWorkHost(id), "\(id) should show the readout")
        }
    }

    /// Prefix matching is the point: build variants ship under their own
    /// identifiers, and Cursor and its relatives get a per-build one.
    func test_buildVariantsMatchByPrefix() {
        XCTAssertTrue(FrontmostAppService.isWorkHost("com.googlecode.iterm2.beta"))
        XCTAssertTrue(FrontmostAppService.isWorkHost("com.microsoft.VSCodeInsiders"))
        XCTAssertTrue(FrontmostAppService.isWorkHost("com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(FrontmostAppService.isWorkHost("com.anthropic.claudefordesktop"))
    }

    func test_everythingElseGetsTheRingOnly() {
        for id in ["com.apple.finder", "com.apple.Safari", "com.spotify.client",
                   "com.tinyspeck.slackmacgap", "com.figma.Desktop", ""] {
            XCTAssertFalse(FrontmostAppService.isWorkHost(id), "\(id) should not show the readout")
        }
    }
}
