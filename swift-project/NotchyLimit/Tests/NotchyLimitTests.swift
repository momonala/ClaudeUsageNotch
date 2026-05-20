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

// MARK: - NotificationService.evaluate() Tests

final class NotificationServiceEvaluateTests: XCTestCase {

    private let defaultsKey = "com.notchylimit.NotificationService.lastFired"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // 5. Jumping from 0% to 75% fires exactly one notification (for 75%),
    //    not three separate ones for 25%, 50%, and 75%.
    func test_evaluate_skippedThresholdsFiredOnce() {
        let service = NotificationService.shared
        let resetAt = Date().addingTimeInterval(3600)

        let window = UsageWindow(
            type: .session,
            percentUsed: 0.76,       // jumped straight past 25% and 50%
            resetAt: resetAt,
            lastUpdated: Date()
        )
        let snapshot = ServiceUsageSnapshot(
            providerId: .claude,
            primaryWindow: window,
            secondaryWindow: nil,
            tertiaryWindow: nil,
            capturedAt: Date()
        )

        service.evaluate(snapshot: snapshot, thresholds: [0.25, 0.5, 0.75, 0.9], providerId: .claude)

        let fired = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        // Keys use hourly buckets, not raw timestamps.
        let bucket = Int(resetAt.timeIntervalSince1970 / 3600)

        // All three crossed thresholds must be marked fired (no future re-fire).
        XCTAssertNotNil(fired["claude:session:0.25:\(bucket)"], "25% should be marked fired")
        XCTAssertNotNil(fired["claude:session:0.5:\(bucket)"],  "50% should be marked fired")
        XCTAssertNotNil(fired["claude:session:0.75:\(bucket)"], "75% should be marked fired")

        // 90% was NOT crossed — must not be in the fired set.
        XCTAssertNil(fired["claude:session:0.9:\(bucket)"], "90% must not be marked fired")

        // A second evaluate at the same usage must not alter the fired set.
        service.evaluate(snapshot: snapshot, thresholds: [0.25, 0.5, 0.75, 0.9], providerId: .claude)
        let firedAfterSecondEval = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        XCTAssertEqual(fired.count, firedAfterSecondEval.count, "second evaluate must not add new entries")
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
