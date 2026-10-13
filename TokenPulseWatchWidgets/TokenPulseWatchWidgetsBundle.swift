import SwiftUI
import WidgetKit

@main
struct TokenPulseWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchQuotaWidget()
    }
}

struct WatchQuotaWidget: Widget {
    let kind = PlatformConstants.watchWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WatchQuotaWidgetIntent.self,
            provider: WatchQuotaTimelineProvider()
        ) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("TokenPulse 额度")
        .description("显示在 TokenPulse Watch App 设置中选择的账号额度。")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#if DEBUG
#Preview("Watch Circular", as: .accessoryCircular) {
    WatchQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}

#Preview("Watch Corner", as: .accessoryCorner) {
    WatchQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}

#Preview("Watch Rectangular", as: .accessoryRectangular) {
    WatchQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}

#Preview("Watch Inline", as: .accessoryInline) {
    WatchQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}
#endif
