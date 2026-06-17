import Foundation
import SQLite3

public enum CodexLocalUsageStore {
    public static func defaultStateURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
    }

    public static func defaultSessionsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    public static func defaultLogsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/logs_2.sqlite")
    }

    public static func defaultLogURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".codex/logs_2.sqlite"),
            home.appendingPathComponent(".codex/sqlite/logs_2.sqlite")
        ]
    }

    public static func loadSummary(
        stateURL: URL = defaultStateURL(),
        logsURL: URL = defaultLogsURL(),
        sessionsURL: URL = defaultSessionsURL(),
        now: Date = Date()
    ) throws -> CodexUsageSummary {
        let logURLs = logsURL == defaultLogsURL() ? defaultLogURLs() : [logsURL]
        if let status = try? loadStatusSummary(logsURLs: logURLs, now: now) {
            return status
        }
        if let rateLimit = try? loadRateLimitSummary(sessionsURL: sessionsURL, now: now) {
            return rateLimit
        }
        return try loadActivitySummary(stateURL: stateURL, now: now)
    }

    public static func loadStatusSummary(
        logsURL: URL = defaultLogsURL(),
        now: Date = Date()
    ) throws -> CodexUsageSummary {
        let logURLs = logsURL == defaultLogsURL() ? defaultLogURLs() : [logsURL]
        return try loadStatusSummary(logsURLs: logURLs, now: now)
    }

    public static func loadStatusSummary(
        logsURLs: [URL],
        now: Date = Date()
    ) throws -> CodexUsageSummary {
        let summaries = logsURLs.compactMap { try? loadLatestStatusSummary(logsURL: $0, now: now) }
        if let latest = summaries.max(by: { ($0.periodEnd ?? .distantPast) < ($1.periodEnd ?? .distantPast) }) {
            return latest
        }
        throw UsageError.decoding("Codex /status rate limit 이벤트를 찾을 수 없습니다.")
    }

    private static func loadLatestStatusSummary(
        logsURL: URL,
        now: Date
    ) throws -> CodexUsageSummary {
        guard FileManager.default.fileExists(atPath: logsURL.path) else {
            throw UsageError.tokenNotFound
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(logsURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw UsageError.network("Codex 로그 DB를 열 수 없습니다.")
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE feedback_log_body LIKE '%"type":"codex.rate_limits"%'
        ORDER BY ts DESC, ts_nanos DESC
        LIMIT 50
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw UsageError.decoding("Codex 로그 DB 쿼리를 준비할 수 없습니다.")
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0)))
            guard let cString = sqlite3_column_text(stmt, 1) else { continue }
            let body = String(cString: cString)
            if let summary = parseStatusLogBody(body, timestamp: timestamp, now: now) {
                return summary
            }
        }
        throw UsageError.decoding("Codex /status rate limit 이벤트를 찾을 수 없습니다.")
    }

    public static func loadRateLimitSummary(
        sessionsURL: URL = defaultSessionsURL(),
        now: Date = Date(),
        maxFiles: Int = 50
    ) throws -> CodexUsageSummary {
        let files = sessionFiles(in: sessionsURL)
        for file in files.prefix(maxFiles) {
            if let summary = try latestRateLimitSummary(in: file, now: now) {
                return summary
            }
        }
        throw UsageError.decoding("Codex rate limit 스냅샷을 찾을 수 없습니다.")
    }

    private static func loadActivitySummary(
        stateURL: URL,
        now: Date
    ) throws -> CodexUsageSummary {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            throw UsageError.tokenNotFound
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(stateURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw UsageError.network("Codex 로컬 상태 DB를 열 수 없습니다.")
        }
        defer { sqlite3_close(db) }

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let sql = """
        SELECT COUNT(*), COALESCE(SUM(tokens_used), 0)
        FROM threads
        WHERE COALESCE(updated_at_ms, updated_at * 1000) >= ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw UsageError.decoding("Codex 로컬 상태 DB 쿼리를 준비할 수 없습니다.")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(start.timeIntervalSince1970 * 1000))
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw UsageError.decoding("Codex 로컬 상태 DB에서 사용량을 읽을 수 없습니다.")
        }

        let threads = Int(sqlite3_column_int64(stmt, 0))
        let tokens = Int(sqlite3_column_int64(stmt, 1))
        return CodexUsageSummary(
            source: "Codex local activity",
            workspaceID: nil,
            periodStart: start,
            periodEnd: now,
            credits: nil,
            threads: threads,
            turns: nil,
            inputTokens: tokens,
            cachedInputTokens: nil,
            outputTokens: nil
        )
    }

    private static func sessionFiles(in sessionsURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.modified > $1.modified }.map(\.url)
    }

    private static func latestRateLimitSummary(in file: URL, now: Date) throws -> CodexUsageSummary? {
        let content = try String(contentsOf: file, encoding: .utf8)
        var latest: CodexUsageSummary?
        var latestDate = Date.distantPast

        for line in content.split(whereSeparator: \.isNewline) {
            guard let summary = parseRateLimitLine(String(line), now: now) else { continue }
            let date = summary.periodEnd ?? .distantPast
            if date >= latestDate {
                latest = summary
                latestDate = date
            }
        }
        return latest
    }

    public static func parseRateLimitLine(_ line: String, now: Date = Date()) -> CodexUsageSummary? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = root["rate_limits"] as? [String: Any] else {
            return nil
        }

        let primary = parseRateLimit(rateLimits["primary"] as? [String: Any])
        let secondary = parseRateLimit(rateLimits["secondary"] as? [String: Any])
        guard primary != nil || secondary != nil else { return nil }

        let timestamp = (root["timestamp"] as? String).flatMap(ISO8601.parse) ?? now
        let planType = rateLimits["plan_type"] as? String
        let credits = number(rateLimits["credits"])

        return CodexUsageSummary(
            source: "Codex rate limit snapshot",
            workspaceID: nil,
            periodStart: nil,
            periodEnd: timestamp,
            primaryRateLimit: primary,
            secondaryRateLimit: secondary,
            additionalRateLimits: [],
            rateLimitPlanType: planType,
            credits: credits,
            threads: nil,
            turns: nil,
            inputTokens: nil,
            cachedInputTokens: nil,
            outputTokens: nil
        )
    }

    public static func parseStatusLogBody(
        _ body: String,
        timestamp: Date,
        now: Date = Date()
    ) -> CodexUsageSummary? {
        guard let event = jsonObjectEmbedded(in: body),
              event["type"] as? String == "codex.rate_limits",
              let rateLimits = event["rate_limits"] as? [String: Any] else {
            return nil
        }

        let primary = parseStatusRateLimit(rateLimits["primary"] as? [String: Any])
        let secondary = parseStatusRateLimit(rateLimits["secondary"] as? [String: Any])
        let additional = parseAdditionalRateLimits(event["additional_rate_limits"] as? [String: Any])
        guard primary != nil || secondary != nil || !additional.isEmpty else { return nil }

        return CodexUsageSummary(
            source: "Codex /status",
            workspaceID: nil,
            periodStart: nil,
            periodEnd: timestamp,
            primaryRateLimit: primary,
            secondaryRateLimit: secondary,
            additionalRateLimits: additional,
            rateLimitPlanType: event["plan_type"] as? String,
            credits: number(event["credits"]),
            threads: nil,
            turns: nil,
            inputTokens: nil,
            cachedInputTokens: nil,
            outputTokens: nil
        )
    }

    private static func parseRateLimit(_ value: [String: Any]?) -> CodexUsageSummary.RateLimit? {
        guard let value, let usedPercent = number(value["used_percent"]) else { return nil }
        let windowMinutes = number(value["window_minutes"]).map(Int.init)
        let resetsAt = number(value["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return CodexUsageSummary.RateLimit(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func parseStatusRateLimit(_ value: [String: Any]?) -> CodexUsageSummary.RateLimit? {
        guard let value, let usedPercent = number(value["used_percent"]) else { return nil }
        let windowMinutes = number(value["window_minutes"]).map(Int.init)
        let resetEpoch = number(value["reset_at"]) ?? number(value["resets_at"])
        let resetsAt = resetEpoch.map { Date(timeIntervalSince1970: $0) }
        return CodexUsageSummary.RateLimit(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func parseAdditionalRateLimits(_ value: [String: Any]?) -> [CodexUsageSummary.NamedRateLimit] {
        guard let value else { return [] }
        var result: [CodexUsageSummary.NamedRateLimit] = []
        for (name, rawLimit) in value {
            guard let limit = rawLimit as? [String: Any] else {
                continue
            }
            let primary = parseStatusRateLimit(limit["primary"] as? [String: Any])
            let secondary = parseStatusRateLimit(limit["secondary"] as? [String: Any])
            guard primary != nil || secondary != nil else { continue }
            result.append(CodexUsageSummary.NamedRateLimit(
                name: name,
                primary: primary,
                secondary: secondary
            ))
        }
        return result.sorted { $0.name < $1.name }
    }

    private static func jsonObjectEmbedded(in text: String) -> [String: Any]? {
        let marker = #""codex.rate_limits""#
        let markerRange = text.range(of: marker)
        let searchEnd = markerRange?.lowerBound ?? text.endIndex
        let prefix = text[..<searchEnd]
        let start = prefix.lastIndex(of: "{") ?? text.firstIndex(of: "{")
        guard let start else { return nil }
        let json = String(text[start...])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
