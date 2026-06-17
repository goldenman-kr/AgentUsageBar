import Foundation

/// Persists the resolved `UsageSnapshot` to the App Group container so the
/// WidgetKit extension can render it without any network or Keychain access.
///
/// The menu-bar app is the sole writer; the widget is a reader. Writes are
/// atomic so the widget never observes a half-written file.
public struct SharedStore {

    public let groupIdentifier: String

    public init(groupIdentifier: String = AppGroup.resolvedIdentifier()) {
        self.groupIdentifier = groupIdentifier
    }

    /// URL of the snapshot file inside the App Group container, or `nil` if the
    /// container is unavailable (e.g. the App Group entitlement isn't granted).
    public var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(AppGroup.snapshotFileName)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @discardableResult
    public func save(_ snapshot: UsageSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        do {
            let data = try Self.encoder().encode(snapshot)
            // Atomic write: the directory is the group container, which exists.
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func load(provider: UsageProvider? = nil) -> UsageSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? Self.decoder().decode(UsageSnapshot.self, from: data) else { return nil }
        if let provider, snapshot.provider != provider { return nil }
        return snapshot
    }
}
