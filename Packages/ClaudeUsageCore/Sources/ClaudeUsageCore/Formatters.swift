import Foundation

/// Derives the human-readable plan label (e.g. "Max (20x)") from the rate-limit
/// tier string, which is available on both the Keychain token and the profile
/// endpoint (e.g. `"default_claude_max_20x"`).
public enum PlanLabel {
    public static func from(rateLimitTier tier: String?, subscriptionType: String? = nil) -> String {
        let t = (tier ?? "").lowercased()
        if t.contains("max_20x") { return "Max (20x)" }
        if t.contains("max_5x") { return "Max (5x)" }
        if t.contains("max") { return "Max" }
        if t.contains("pro") { return "Pro" }
        if t.contains("team") { return "Team" }
        if t.contains("enterprise") { return "Enterprise" }
        if t.contains("free") { return "Free" }
        switch (subscriptionType ?? "").lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "free": return "Free"
        default: return "Claude"
        }
    }
}

public enum CodexPlanLabel {
    public static func from(planType: String?) -> String {
        switch (planType ?? "").lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team", "business": return "Business"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        case "go": return "Go"
        case "api": return "API Key"
        default: return "Codex"
        }
    }
}

/// Formats reset timestamps to match the desktop app's "사용량" page wording.
public enum ResetFormatter {

    /// Short relative form used for the rolling 5-hour session window:
    /// "3시간 58분 후 재설정". Falls back to an absolute time if `resetsAt` is far out.
    public static func relative(_ resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else { return "" }
        let seconds = resetsAt.timeIntervalSince(now)
        // Anything under a minute (incl. already-passed) reads as "곧 재설정";
        // this also prevents a misleading "0분 후 재설정" for 1–59s remaining.
        if seconds < 60 { return "곧 재설정" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)시간 \(minutes)분 후 재설정" }
        if hours > 0 { return "\(hours)시간 후 재설정" }
        return "\(minutes)분 후 재설정"
    }

    /// Absolute weekday + time form used for the weekly window:
    /// "수 오후 7:59에 재설정".
    public static func absolute(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("EEE a h:mm")
        return "\(f.string(from: resetsAt))에 재설정"
    }

    /// "1분 전" style age used for the "마지막 업데이트" line.
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "방금" }
        if seconds < 60 { return "\(Int(seconds))초 전" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)분 전" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)시간 전" }
        return "\(hours / 24)일 전"
    }
}

/// Parses the API's ISO-8601 timestamps, which carry microsecond precision and
/// a `±HH:MM` offset (e.g. `2026-06-15T05:59:59.553366+00:00`).
public enum ISO8601 {
    public static func parse(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: string) { return d }

        // Normalize variable-length fractional seconds to 3 digits and retry.
        if let normalized = normalizeFractionalSeconds(string),
           let d = withFractional.date(from: normalized) {
            return d
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Truncates/pads the fractional-seconds component to exactly 3 digits so
    /// `ISO8601DateFormatter` accepts microsecond timestamps on all OS versions.
    static func normalizeFractionalSeconds(_ s: String) -> String? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        var i = s.index(after: dot)
        var digits = ""
        while i < s.endIndex, s[i].isNumber {
            digits.append(s[i])
            i = s.index(after: i)
        }
        guard !digits.isEmpty else { return nil }
        let three = String((digits + "000").prefix(3))
        return String(s[s.startIndex..<s.index(after: dot)]) + three + String(s[i...])
    }
}
