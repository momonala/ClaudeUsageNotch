import XCTest
@testable import NotchyLimit

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

        XCTAssertEqual(snapshot.providerId, .claude)
        XCTAssertEqual(snapshot.primaryWindow.percentUsed, 0.425, accuracy: 0.001)
        XCTAssertEqual(snapshot.secondaryWindow?.percentUsed, 0.610, accuracy: 0.001)
        XCTAssertEqual(snapshot.tertiaryWindow?.percentUsed, 0.280, accuracy: 0.001)
        XCTAssertNotNil(snapshot.primaryWindow.resetAt)
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

    // 4. Missing optional windows → secondaryWindow and tertiaryWindow are nil.
    func test_snapshot_optionalWindowsAreNil() throws {
        let json = """
        { "five_hour": { "utilization": 10.0, "resets_at": null } }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: json)
        let snapshot = try ClaudeUsageMapper.snapshot(from: dto)

        XCTAssertNil(snapshot.secondaryWindow)
        XCTAssertNil(snapshot.tertiaryWindow)
        XCTAssertNil(snapshot.primaryWindow.resetAt)
    }
}

// MARK: - NotificationService high-water mark tests

final class NotificationServiceEvaluateTests: XCTestCase {

    private let defaultsKey = "com.notchylimit.NotificationService.highWaterMark"
    private let thresholds: [Double] = [0.25, 0.5, 0.75, 0.9]

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func snapshot(percent: Double) -> ServiceUsageSnapshot {
        ServiceUsageSnapshot(
            providerId: .claude,
            primaryWindow: UsageWindow(type: .session, percentUsed: percent,
                                       lastUpdated: Date()),
            secondaryWindow: nil,
            tertiaryWindow: nil,
            capturedAt: Date()
        )
    }

    private func mark() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    }

    // 5a. Skipping thresholds: jumping from 0% to 76% records the 75% mark
    //     and does not fire separately for 25% or 50%.
    func test_skippedThresholds_recordsHighestOnly() {
        let service = NotificationService.shared
        service.evaluate(snapshot: snapshot(percent: 0.76),
                         thresholds: thresholds, providerId: .claude)

        XCTAssertEqual(mark()["claude:session"], 0.75,
                       "mark should be 0.75 — the highest crossed threshold")
    }

    // 5b. Repeated polls at the same usage level fire nothing extra.
    func test_repeatedEvaluate_doesNotReFire() {
        let service = NotificationService.shared
        service.evaluate(snapshot: snapshot(percent: 0.76),
                         thresholds: thresholds, providerId: .claude)
        let markAfterFirst = mark()

        service.evaluate(snapshot: snapshot(percent: 0.76),
                         thresholds: thresholds, providerId: .claude)
        XCTAssertEqual(mark(), markAfterFirst,
                       "mark must not change on a second evaluate at the same usage")
    }

    // 5c. Crossing a higher threshold on a later poll fires once more.
    func test_newHigher_threshold_fires() {
        let service = NotificationService.shared
        service.evaluate(snapshot: snapshot(percent: 0.76),
                         thresholds: thresholds, providerId: .claude)
        XCTAssertEqual(mark()["claude:session"], 0.75)

        service.evaluate(snapshot: snapshot(percent: 0.92),
                         thresholds: thresholds, providerId: .claude)
        XCTAssertEqual(mark()["claude:session"], 0.9,
                       "mark should advance to 0.9 when usage crosses 90%")
    }

    // 5d. Window reset: usage drops below the lowest threshold → mark clears →
    //     next rising edge fires fresh notifications.
    func test_windowReset_clearsMark() {
        let service = NotificationService.shared
        service.evaluate(snapshot: snapshot(percent: 0.76),
                         thresholds: thresholds, providerId: .claude)
        XCTAssertEqual(mark()["claude:session"], 0.75)

        // Simulate window reset — usage back near zero.
        service.evaluate(snapshot: snapshot(percent: 0.05),
                         thresholds: thresholds, providerId: .claude)
        XCTAssertEqual(mark()["claude:session"], 0,
                       "mark should clear to 0 when usage drops below lowest threshold")

        // Next rising edge should fire again.
        service.evaluate(snapshot: snapshot(percent: 0.76),
                         thresholds: thresholds, providerId: .claude)
        XCTAssertEqual(mark()["claude:session"], 0.75,
                       "mark should advance again after window reset")
    }

    // 6. KeychainStore round-trip: write → read → delete.
    func test_keychainStore_roundTrip() {
        let store = KeychainStore(service: "com.notchylimit.tests.\(UUID().uuidString)")
        let payload = "test-payload-\(UUID().uuidString)".data(using: .utf8)!

        store.set(account: "roundtrip", data: payload)
        let read = store.get(account: "roundtrip")
        XCTAssertEqual(read, payload)

        let deleted = store.delete(account: "roundtrip")
        XCTAssertTrue(deleted)
        XCTAssertNil(store.get(account: "roundtrip"))
    }
}
