import Foundation

/// Centralized constants for the Claude usage data pipeline.
///
/// These values were reverse-engineered from the Claude Code CLI bundle and
/// verified against the live `api.anthropic.com` OAuth endpoints. The widget
/// reuses the OAuth access token that the Claude Code CLI (or the Claude
/// desktop app) already stores in the macOS Keychain — it never performs an
/// interactive login of its own.
public enum ClaudeAPI {
    /// `GET` — returns the subscription usage limits shown in the desktop app's
    /// "사용량" settings page (current session + weekly limits).
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// `GET` — returns the account / organization profile, used here only to
    /// derive the human-readable plan label (e.g. "Max (20x)").
    public static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    /// Required beta header for OAuth-token (non-API-key) requests.
    public static let oauthBetaHeader = "oauth-2025-04-20"

    /// User-Agent mirrors the Claude Code CLI so the endpoint behaves identically.
    public static let userAgent = "claude-cli/2.1.177 (external, claude-usage-widget)"
}

public enum CodexAuth {
    public static let userAgent = "codex-usage-bar/1.0"

    public static func defaultAuthFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex/auth.json")
    }

    public static func analyticsUsageURL(workspaceID: String) -> URL {
        URL(string: "https://api.chatgpt.com/v1/analytics/codex/workspaces/\(workspaceID)/usage")!
    }
}

/// Identifiers shared between the menu-bar app and the WidgetKit extension.
public enum AppGroup {
    /// Info.plist key holding the real App Group id. Both targets set it via a
    /// build setting to `group.$(DEVELOPMENT_TEAM).com.hubinsoft.claudeusage`.
    ///
    /// On macOS (Sonoma+), the App Group identifier MUST be prefixed with the
    /// signing Team ID, otherwise a non-sandboxed app is denied access to the
    /// container and `containerURL(...)` returns nil. Because the Team ID isn't
    /// known until signing, we resolve the id from the built Info.plist at
    /// runtime rather than hard-coding it.
    public static let infoPlistKey = "AppGroupIdentifier"

    /// Used only in unsigned/local contexts where the App Group is non-functional
    /// anyway (the menu-bar app still works; it just can't feed the widget).
    public static let fallbackIdentifier = "group.com.hubinsoft.claudeusage"

    /// File name of the persisted usage snapshot inside the group container.
    public static let snapshotFileName = "usage-snapshot.json"

    /// WidgetKit kind identifier.
    public static let widgetKind = "ClaudeUsageWidget"

    /// Resolves the Team-ID-prefixed App Group id from the running bundle's
    /// Info.plist (app bundle for the app, appex bundle for the widget — both
    /// expand to the same string). Falls back when unset or not yet expanded.
    public static func resolvedIdentifier(bundle: Bundle = .main) -> String {
        if let value = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
           value.hasPrefix("group."), !value.contains("$("), !value.contains("..") {
            return value
        }
        return fallbackIdentifier
    }
}

/// macOS Keychain coordinates for the credential created by the Claude Code CLI.
public enum KeychainCoordinates {
    /// Generic-password service name. The CLI stores the active credential under
    /// the un-suffixed service; per-account copies use a `-<hash>` suffix.
    public static let service = "Claude Code-credentials"
}
