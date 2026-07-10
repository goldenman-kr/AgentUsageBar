import SwiftUI
import ClaudeUsageCore

/// One usage metric rendered as: title + percentage on the right, a meter bar,
/// and a caption underneath (reset time or status). Mirrors the rows on the
/// desktop app's "사용량" page.
public struct MetricRow: View {
    public struct TimeProgress: Sendable, Equatable {
        public let elapsedFraction: Double
        public let accessibilityLabel: String

        public init?(windowMinutes: Int?, resetsAt: Date?, now: Date = Date()) {
            guard let windowMinutes, windowMinutes > 0, let resetsAt else { return nil }
            let totalSeconds = Double(windowMinutes * 60)
            let remainingSeconds = max(0, resetsAt.timeIntervalSince(now))
            let elapsed = min(max((totalSeconds - remainingSeconds) / totalSeconds, 0), 1)
            elapsedFraction = elapsed
            accessibilityLabel = "\(Int((elapsed * 100).rounded()))% 시간 경과"
        }
    }

    public let title: String
    public let metric: Metric
    public let caption: String
    public let timeProgress: TimeProgress?

    public init(title: String, metric: Metric, caption: String, timeProgress: TimeProgress? = nil) {
        self.title = title
        self.metric = metric
        self.caption = caption
        self.timeProgress = timeProgress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(Int(metric.utilization.rounded()))% 사용됨")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            MeterBar(fraction: metric.fraction, utilization: metric.utilization)
            if let timeProgress {
                TimeElapsedBar(progress: timeProgress)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct TimeElapsedBar: View {
    let progress: MetricRow.TimeProgress
    private let height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(UsagePalette.track)
                Capsule(style: .continuous)
                    .fill(UsagePalette.timeElapsed)
                    .frame(width: geo.size.width * progress.elapsedFraction)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(progress.accessibilityLabel)
    }
}
