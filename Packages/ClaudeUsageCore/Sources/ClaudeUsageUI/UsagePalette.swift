import SwiftUI
import ClaudeUsageCore

/// Color thresholds shared by the menu-bar popover and the widget.
public enum UsagePalette {
    /// Bar fill color that escalates with utilization (blue → orange → red),
    /// a common, scannable usability pattern.
    public static func color(for utilization: Double) -> Color {
        switch utilization {
        case ..<70: return Color.accentColor
        case 70..<90: return Color.orange
        default: return Color.red
        }
    }

    /// Subtle track color behind the fill.
    public static var track: Color { Color.primary.opacity(0.12) }
}

/// A rounded progress meter matching the desktop app's thin usage bars.
public struct MeterBar: View {
    public let fraction: Double
    public let utilization: Double
    public var height: CGFloat

    public init(fraction: Double, utilization: Double, height: CGFloat = 6) {
        self.fraction = fraction
        self.utilization = utilization
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(UsagePalette.track)
                Capsule(style: .continuous)
                    .fill(UsagePalette.color(for: utilization))
                    .frame(width: max(height, geo.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(Int(utilization))% 사용됨")
    }
}
