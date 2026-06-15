import XCTest
@testable import ClaudeUsageCore

final class ClaudeUsageCoreTests: XCTestCase {

    // MARK: Keychain token decoding

    func testDecodeToken() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat-XXXX",
            "refreshToken": "sk-ant-ort-YYYY",
            "expiresAt": 1781514393211,
            "scopes": ["user:inference", "user:profile"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x"
          },
          "organizationUuid": "00000000-0000-0000-0000-000000000000"
        }
        """.data(using: .utf8)!
        let token = try KeychainTokenStore.decodeToken(from: json)
        XCTAssertEqual(token.accessToken, "sk-ant-oat-XXXX")
        XCTAssertEqual(token.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(token.subscriptionType, "max")
        XCTAssertEqual(token.expiresAt.timeIntervalSince1970, 1781514393.211, accuracy: 0.01)
    }

    func testDecodeTokenRejectsMalformed() {
        let json = #"{ "foo": "bar" }"#.data(using: .utf8)!
        XCTAssertThrowsError(try KeychainTokenStore.decodeToken(from: json))
    }

    // MARK: ISO-8601 parsing (microsecond precision + offset)

    func testISO8601Microseconds() {
        let d = ISO8601.parse("2026-06-15T05:59:59.553366+00:00")
        XCTAssertNotNil(d)
        // 2026-06-15T05:59:59Z ≈ epoch
        XCTAssertEqual(d!.timeIntervalSince1970, 1781503199.553, accuracy: 1.0)
    }

    func testISO8601NoFraction() {
        XCTAssertNotNil(ISO8601.parse("2026-06-17T10:59:59+00:00"))
    }

    func testNormalizeFractionalSeconds() {
        XCTAssertEqual(
            ISO8601.normalizeFractionalSeconds("2026-06-15T05:59:59.553366+00:00"),
            "2026-06-15T05:59:59.553+00:00"
        )
        XCTAssertEqual(
            ISO8601.normalizeFractionalSeconds("2026-06-15T05:59:59.5+00:00"),
            "2026-06-15T05:59:59.500+00:00"
        )
    }

    // MARK: Usage response decoding (real captured shape)

    func testUsageResponseDecoding() throws {
        let json = """
        {
          "five_hour": { "utilization": 7.0, "resets_at": "2026-06-15T05:59:59.553366+00:00" },
          "seven_day": { "utilization": 11.0, "resets_at": "2026-06-17T10:59:59.553386+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": {
            "is_enabled": true, "monthly_limit": 2000, "used_credits": 0.0,
            "utilization": null, "currency": "USD", "disabled_reason": null
          }
        }
        """.data(using: .utf8)!
        let usage = try UsageAPIClient.makeDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(usage.fiveHour?.utilization, 7.0)
        XCTAssertNotNil(usage.fiveHour?.resetsAt)
        XCTAssertEqual(usage.sevenDay?.utilization, 11.0)
        XCTAssertNil(usage.sevenDayOpus)                 // bucket entirely null
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 0.0)
        XCTAssertNil(usage.sevenDaySonnet?.resetsAt)     // used but never reset
        XCTAssertEqual(usage.extraUsage?.isEnabled, true)
        XCTAssertEqual(usage.extraUsage?.monthlyLimit, 2000)
    }

    func testSnapshotMappingFromUsage() throws {
        let json = """
        { "five_hour": { "utilization": 42.5, "resets_at": null },
          "seven_day": { "utilization": 80.0, "resets_at": null },
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": { "is_enabled": false } }
        """.data(using: .utf8)!
        let usage = try UsageAPIClient.makeDecoder().decode(UsageResponse.self, from: json)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = UsageSnapshot(usage: usage, planLabel: "Max (20x)", fetchedAt: now)
        XCTAssertEqual(snap.session.utilization, 42.5)
        XCTAssertEqual(snap.session.fraction, 0.425, accuracy: 0.0001)
        XCTAssertEqual(snap.weeklyAll.utilization, 80.0)
        XCTAssertEqual(snap.weeklySonnet?.utilization, 0.0)
        XCTAssertNil(snap.weeklyOpus)
        XCTAssertNil(snap.extra)                          // disabled → dropped
        XCTAssertEqual(snap.fetchedAt, now)
    }

    func testFractionClamping() {
        XCTAssertEqual(Metric(utilization: 150, resetsAt: nil).fraction, 1.0)
        XCTAssertEqual(Metric(utilization: -5, resetsAt: nil).fraction, 0.0)
    }

    // MARK: Plan label

    func testPlanLabel() {
        XCTAssertEqual(PlanLabel.from(rateLimitTier: "default_claude_max_20x"), "Max (20x)")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: "default_claude_max_5x"), "Max (5x)")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: "claude_pro"), "Pro")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: nil, subscriptionType: "max"), "Max")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: nil, subscriptionType: nil), "Claude")
    }

    // MARK: Reset formatting

    func testRelativeReset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let in3h58m = now.addingTimeInterval(3 * 3600 + 58 * 60)
        XCTAssertEqual(ResetFormatter.relative(in3h58m, now: now), "3시간 58분 후 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(45 * 60), now: now), "45분 후 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(-10), now: now), "곧 재설정")
        // Sub-60s remaining must read "곧 재설정", never a misleading "0분 후 재설정".
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(30), now: now), "곧 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(59), now: now), "곧 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(60), now: now), "1분 후 재설정")
        XCTAssertEqual(ResetFormatter.relative(nil), "")
    }

    func testAge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ResetFormatter.age(now.addingTimeInterval(-90), now: now), "1분 전")
        XCTAssertEqual(ResetFormatter.age(now.addingTimeInterval(-5), now: now), "방금")
    }

    // MARK: Retry-After parsing (429 backoff)

    func testRetryAfterSecondsNumeric() throws {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                   headerFields: ["Retry-After": "90"])!
        XCTAssertEqual(UsageAPIClient.retryAfterSeconds(from: resp), 90)
    }

    func testRetryAfterSecondsHTTPDate() throws {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                   headerFields: ["Retry-After": "Tue, 14 Nov 2023 22:18:20 GMT"])!
        let secs = UsageAPIClient.retryAfterSeconds(from: resp, now: now)
        XCTAssertNotNil(secs)
        XCTAssertEqual(secs!, 1_700_000_300 - 1_700_000_000, accuracy: 1.0)
    }

    func testRetryAfterAbsent() throws {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: [:])!
        XCTAssertNil(UsageAPIClient.retryAfterSeconds(from: resp))
    }

    // MARK: Snapshot codec round-trip (widget read path)

    func testSnapshotRoundTrip() throws {
        let snap = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            planLabel: "Max (20x)",
            session: Metric(utilization: 7, resetsAt: Date(timeIntervalSince1970: 1_700_010_000)),
            weeklyAll: Metric(utilization: 11, resetsAt: nil),
            weeklySonnet: Metric(utilization: 0, resetsAt: nil),
            weeklyOpus: nil,
            extra: ExtraInfo(isEnabled: true, monthlyLimit: 2000, usedCredits: 3.5, currency: "USD"),
            errorMessage: nil
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(snap)
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.session.utilization, 7)
        XCTAssertEqual(decoded.weeklyAll.utilization, 11)
        XCTAssertEqual(decoded.extra?.usedCredits, 3.5)
        XCTAssertEqual(decoded.planLabel, "Max (20x)")
    }
}
