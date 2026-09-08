import SwiftUI
import WidgetKit

@main
struct TokenPulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PhoneQuotaWidget()
    }
}

struct PhoneQuotaWidget: Widget {
    let kind = "TokenPulsePhoneQuota"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuotaWidgetIntent.self, provider: QuotaTimelineProvider()) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("TokenPulse 额度")
        .description("在同一个组件中显示账号所需的每周或 5 小时额度。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
