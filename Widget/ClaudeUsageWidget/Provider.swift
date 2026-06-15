import WidgetKit
import ClaudeUsageCore

/// One timeline entry = one usage snapshot. The widget is a pure reader of the
/// snapshot the menu-bar app persists to the App Group container, so it never
/// performs network or Keychain access (and never burns WidgetKit's refresh
/// budget on I/O it can't control).
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    /// True when no snapshot exists yet — prompt the user to launch the app.
    let needsApp: Bool
}

struct Provider: TimelineProvider {
    private let store = SharedStore()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: samplePreview, needsApp: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = currentEntry()
        // The app pushes reloads on every fetch; this is a safety-net cadence.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> UsageEntry {
        if let snap = store.load() {
            return UsageEntry(date: Date(), snapshot: snap, needsApp: false)
        }
        return UsageEntry(
            date: Date(),
            snapshot: .placeholder(error: "메뉴바 앱을 실행하세요"),
            needsApp: true
        )
    }

    /// Static data used only for the gallery preview / placeholder.
    private var samplePreview: UsageSnapshot {
        UsageSnapshot(
            fetchedAt: Date(),
            planLabel: "Max (20x)",
            session: Metric(utilization: 9, resetsAt: Date().addingTimeInterval(3 * 3600 + 45 * 60)),
            weeklyAll: Metric(utilization: 11, resetsAt: nil),
            weeklySonnet: Metric(utilization: 0, resetsAt: nil),
            weeklyOpus: nil,
            extra: nil
        )
    }
}
