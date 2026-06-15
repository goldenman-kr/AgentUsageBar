import SwiftUI
import ClaudeUsageCore

/// One usage metric rendered as: title + percentage on the right, a meter bar,
/// and a caption underneath (reset time or status). Mirrors the rows on the
/// desktop app's "사용량" page.
public struct MetricRow: View {
    public let title: String
    public let metric: Metric
    public let caption: String

    public init(title: String, metric: Metric, caption: String) {
        self.title = title
        self.metric = metric
        self.caption = caption
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
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
