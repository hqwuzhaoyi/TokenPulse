import AppIntents
import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let accounts: [WidgetAccountSnapshot]
    let selectionRequired: Bool
    let accountSelectionMissing: Bool
    let hasAvailableAccounts: Bool
}

struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<QuotaWidgetIntent>] {
        [AppIntentRecommendation(intent: QuotaWidgetIntent(), description: "选择 TokenPulse 账号")]
    }

    func placeholder(in context: Context) -> QuotaWidgetEntry {
        WidgetPlaceholder.entry(family: presentationFamily(context.family))
    }

    func snapshot(for configuration: QuotaWidgetIntent, in context: Context) async -> QuotaWidgetEntry {
        await entry(for: configuration, family: presentationFamily(context.family))
    }

    func timeline(for configuration: QuotaWidgetIntent, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        let entry = await entry(for: configuration, family: presentationFamily(context.family))
        let dates = Set(entry.accounts.flatMap(\.windows).compactMap(\.resetsAt))
            .filter { $0 > entry.date }.sorted()
        return Timeline(
            entries: [entry] + dates.map {
                QuotaWidgetEntry(
                    date: $0,
                    accounts: entry.accounts,
                    selectionRequired: entry.selectionRequired,
                    accountSelectionMissing: entry.accountSelectionMissing,
                    hasAvailableAccounts: entry.hasAvailableAccounts
                )
            },
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
    }

    private func entry(
        for configuration: QuotaWidgetIntent,
        family: WidgetPresentationFamily
    ) async -> QuotaWidgetEntry {
        let snapshots = await WidgetSnapshotStore().load()
        let selectedIDs = (configuration.accounts ?? []).compactMap { UUID(uuidString: $0.id) }
        let selection = WidgetPresentation.select(snapshots, selectedIDs: selectedIDs, family: family)
        return QuotaWidgetEntry(
            date: Date(),
            accounts: selection.accounts,
            selectionRequired: selection.selectionRequired,
            accountSelectionMissing: selection.accountSelectionMissing,
            hasAvailableAccounts: selection.hasAvailableAccounts
        )
    }

    private func presentationFamily(_ family: WidgetFamily) -> WidgetPresentationFamily {
        #if os(iOS)
        switch family {
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        default: .single
        }
        #else
        .single
        #endif
    }
}

struct WatchQuotaTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<WatchQuotaWidgetIntent>] {
        [AppIntentRecommendation(intent: WatchQuotaWidgetIntent(), description: "选择 TokenPulse 账号")]
    }

    func placeholder(in context: Context) -> QuotaWidgetEntry {
        WidgetPlaceholder.entry(family: .single)
    }

    func snapshot(for configuration: WatchQuotaWidgetIntent, in context: Context) async -> QuotaWidgetEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: WatchQuotaWidgetIntent, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        let entry = await entry(for: configuration)
        let dates = Set(entry.accounts.flatMap(\.windows).compactMap(\.resetsAt))
            .filter { $0 > entry.date }.sorted()
        return Timeline(
            entries: [entry] + dates.map {
                QuotaWidgetEntry(
                    date: $0,
                    accounts: entry.accounts,
                    selectionRequired: entry.selectionRequired,
                    accountSelectionMissing: entry.accountSelectionMissing,
                    hasAvailableAccounts: entry.hasAvailableAccounts
                )
            },
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
    }

    private func entry(for configuration: WatchQuotaWidgetIntent) async -> QuotaWidgetEntry {
        let snapshots = await WidgetSnapshotStore().load()
        let configuredID = await WatchWidgetSelectionStore().load()
        let selectedID = configuredID.flatMap { id in snapshots.contains { $0.id == id } ? id : nil }
            ?? snapshots.first?.id
        let selectedIDs = selectedID.map { [$0] } ?? []
        let selection = WidgetPresentation.select(snapshots, selectedIDs: selectedIDs, family: .single)
        return QuotaWidgetEntry(
            date: Date(),
            accounts: selection.accounts,
            selectionRequired: selection.selectionRequired,
            accountSelectionMissing: selection.accountSelectionMissing,
            hasAvailableAccounts: selection.hasAvailableAccounts
        )
    }
}

private enum WidgetPlaceholder {
    static func entry(family: WidgetPresentationFamily, date: Date = Date()) -> QuotaWidgetEntry {
        let accounts = snapshots(at: date)
        let selection = WidgetPresentation.select(
            accounts,
            selectedIDs: Array(accounts.prefix(family.accountLimit)).map(\.id),
            family: family
        )
        return QuotaWidgetEntry(
            date: date,
            accounts: selection.accounts,
            selectionRequired: false,
            accountSelectionMissing: false,
            hasAvailableAccounts: true
        )
    }

    static func snapshots(at date: Date) -> [WidgetAccountSnapshot] {
        [
            snapshot(
                name: "MiniMax 国内", provider: .miniMaxChina,
                windows: [window(id: "minimax.five", name: "5 小时额度", period: .fiveHour,
                                 used: 46, reset: date.addingTimeInterval(2 * 3_600))]
            ),
            snapshot(
                name: "GLM 工作号", provider: .zai,
                windows: [
                    window(id: "glm.weekly", name: "每周额度", period: .weekly,
                           used: 38, reset: date.addingTimeInterval(3 * 86_400)),
                    window(id: "glm.five", name: "5 小时额度", period: .fiveHour,
                           used: 71, reset: date.addingTimeInterval(58 * 60)),
                ]
            ),
            snapshot(
                name: "Codex 团队号", provider: .codex,
                windows: [
                    window(id: "codex.five", name: "5 小时额度", period: .fiveHour,
                           used: 52, reset: date.addingTimeInterval(4 * 3_600)),
                    window(id: "codex.weekly", name: "每周额度", period: .weekly,
                           used: 84, reset: date.addingTimeInterval(5 * 86_400)),
                ],
                resetCount: 3,
                plan: .plus
            ),
            snapshot(
                name: "SuperGrok", provider: .superGrok,
                windows: [window(id: "superGrok.pool", name: "每周额度", period: .weekly,
                                 used: 67, reset: date.addingTimeInterval(4 * 86_400))]
            ),
        ]
    }

    private static func snapshot(
        name: String,
        provider: Provider,
        windows: [QuotaWindow],
        resetCount: Int? = nil,
        plan: SubscriptionPlan? = nil
    ) -> WidgetAccountSnapshot {
        WidgetAccountSnapshot(
            account: SubscriptionAccount(name: name, provider: provider),
            windows: windows,
            collectedAt: Date(),
            lastFailure: nil,
            remainingResetCount: resetCount,
            subscriptionPlan: plan
        )
    }

    private static func window(
        id: String,
        name: String,
        period: QuotaPeriod,
        used: Double,
        reset: Date
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            name: name,
            scope: nil,
            period: period,
            usedPercentage: used,
            remainingCount: nil,
            totalCount: nil,
            resetsAt: reset
        )
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaWidgetEntry

    var body: some View {
        Group {
            if entry.accounts.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
            } else {
                content
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color.black }
        .widgetURL(widgetURL)
    }

    @ViewBuilder
    private var content: some View {
        #if os(watchOS)
        if family == .accessoryCorner {
            accessoryCorner(entry.accounts[0])
        } else if family == .accessoryInline {
            inline(entry.accounts[0])
        } else if family == .accessoryCircular {
            accessoryCircular(entry.accounts[0])
        } else if family == .accessoryRectangular {
            accessoryRectangular(entry.accounts[0])
        } else {
            small(entry.accounts[0])
        }
        #else
        if family == .accessoryInline {
            inline(entry.accounts[0])
        } else if family == .accessoryCircular {
            accessoryCircular(entry.accounts[0])
        } else if family == .accessoryRectangular {
            accessoryRectangular(entry.accounts[0])
        } else {
            switch family {
            case .systemMedium:
                medium
            case .systemLarge, .systemExtraLarge:
                large
            default:
                small(entry.accounts[0])
            }
        }
        #endif
    }

    #if os(watchOS)
    @ViewBuilder
    private func accessoryCorner(_ account: WidgetAccountSnapshot) -> some View {
        if let metric = account.displayMetrics.first {
            ProviderIcon(provider: account.account.provider, size: 20)
                .widgetLabel {
                    if let fraction = metric.ringFraction {
                        Gauge(value: fraction) {
                            Text("重置 \(QuotaFormatting.resetDate(metric.window?.resetsAt))")
                        } currentValueLabel: {
                            Text(metric.valueText)
                        }
                    } else {
                        Text("\(metric.title) \(metric.valueText)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary(account))
        } else {
            ProviderIcon(provider: account.account.provider, size: 20)
                .widgetLabel("额度未提供")
                .accessibilityLabel("\(account.account.name)，额度未提供")
        }
    }
    #endif

    private func inline(_ account: WidgetAccountSnapshot) -> some View {
        let metrics = account.ringMetrics
        return Text(
            "\(account.account.name) "
                + metrics.map { "\($0.title) \($0.valueText)" }.joined(separator: " · ")
                + resetCountSuffix(account)
                + availabilitySuffix(account)
        )
    }

    @ViewBuilder
    private func accessoryCircular(_ account: WidgetAccountSnapshot) -> some View {
        if let metric = account.displayMetrics.first, metric.window?.wallet != nil || metric.window == nil {
            VStack(spacing: 1) {
                ProviderIcon(provider: account.account.provider, size: 11)
                Text(metric.valueText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(account))
        } else {
            ZStack {
                if let metric = account.displayMetrics.first {
                    QuotaRing(metric: metric, diameter: 58, lineWidth: 5)
                }
                VStack(spacing: 1) {
                    ProviderIcon(provider: account.account.provider, size: 11)
                    if let metric = account.displayMetrics.first {
                        Text(metric.valueText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(account))
        }
    }

    private func accessoryRectangular(_ account: WidgetAccountSnapshot) -> some View {
        HStack(spacing: 8) {
            if let metric = account.displayMetrics.first {
                if metric.window?.wallet != nil || metric.window == nil {
                    ProviderIcon(provider: account.account.provider, size: 22)
                } else {
                    QuotaRing(metric: metric, diameter: 48, lineWidth: 5)
                        .overlay {
                        Text(metric.valueText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.65)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ProviderIcon(provider: account.account.provider, size: 10)
                    Text(account.account.name).font(.caption2.bold()).lineLimit(1)
                }
                if let metric = account.displayMetrics.first {
                    Text(metric.title).font(.caption2).lineLimit(1)
                    Text(resetText(metric)).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(account))
    }

    private func small(_ account: WidgetAccountSnapshot) -> some View {
        let metrics = account.ringMetrics
        return VStack(spacing: 7) {
            AccountHeader(account: account, date: entry.date)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ForEach(metrics) { metric in
                    RingMetric(metric: metric, diameter: metrics.count == 1 ? 76 : metrics.count == 3 ? 38 : 55)
                }
            }
            Spacer(minLength: 0)
            AccountStatus(account: account)
        }
    }

    private var medium: some View {
        HStack(spacing: 8) {
            ForEach(entry.accounts.prefix(2)) { account in
                accountLink(account) {
                    AccountTile(account: account, date: entry.date, ringDiameter: 44)
                }
            }
        }
    }

    private var large: some View {
        VStack(spacing: 6) {
            LazyVGrid(
                columns: entry.accounts.count == 1
                    ? [GridItem(.flexible())]
                    : [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(entry.accounts.prefix(4)) { account in
                    accountLink(account) {
                        AccountTile(
                            account: account,
                            date: entry.date,
                            ringDiameter: entry.accounts.count <= 2 ? 76 : 52
                        )
                    }
                    .frame(minHeight: entry.accounts.count <= 2 ? 250 : 120)
                }
            }
            if entry.accountSelectionMissing {
                Text("部分账号尚未同步")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func accountLink<Content: View>(
        _ account: WidgetAccountSnapshot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let url = accountURL(account) {
            Link(destination: url) { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }

    private var widgetURL: URL? {
        guard entry.accounts.count == 1 else { return PlatformConstants.accountsDeepLink }
        return accountURL(entry.accounts[0])
    }

    private var emptyMessage: String {
        if entry.accountSelectionMissing { return "所选账号尚未同步" }
        if entry.selectionRequired && entry.hasAvailableAccounts { return "请选择展示账号" }
        return "请先添加账号"
    }

    private func accountURL(_ account: WidgetAccountSnapshot) -> URL? {
        PlatformConstants.accountDeepLink(for: account.id)
    }

    private func resetCountSuffix(_ account: WidgetAccountSnapshot) -> String {
        guard account.supportsManualResetCount else { return "" }
        return " · 可重置 \(QuotaFormatting.remainingResets(account.remainingResetCount))"
    }

    private func resetText(_ metric: WidgetQuotaMetric) -> String {
        guard let window = metric.window else { return "时间未提供" }
        if window.wallet != nil { return "钱包余额" }
        if let expiresAt = window.expiresAt { return "到期 \(QuotaFormatting.resetDate(expiresAt))" }
        return "重置 \(QuotaFormatting.resetDate(window.resetsAt))"
    }

    private func accessibilitySummary(_ account: WidgetAccountSnapshot) -> String {
        let metrics = account.displayMetrics.map {
            "\($0.title) \($0.valueText)，\(resetText($0))"
        }.joined(separator: "；")
        return "\(account.account.name)，\(metrics)\(resetCountSuffix(account))\(availabilitySuffix(account))"
    }

    private func availabilitySuffix(_ account: WidgetAccountSnapshot) -> String {
        if account.walletAvailable == false { return " · API 不可用" }
        if account.quotaExceeded == true { return " · 额度已用尽" }
        return ""
    }
}

private struct AccountHeader: View {
    let account: WidgetAccountSnapshot
    let date: Date

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: account.account.provider, size: 14)
            Text(account.account.name).font(.caption.bold()).lineLimit(1)
            Spacer(minLength: 0)
            if account.supportsManualResetCount {
                Text("可重置 \(QuotaFormatting.remainingResets(account.remainingResetCount))")
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            if account.walletAvailable == false || account.quotaExceeded == true {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(account.walletAvailable == false ? "API 不可用" : "额度已用尽")
            }
            if account.needsUpdate(at: date) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .accessibilityLabel("待更新")
            }
        }
    }
}

private struct AccountTile: View {
    let account: WidgetAccountSnapshot
    let date: Date
    let ringDiameter: CGFloat

    var body: some View {
        let metrics = account.ringMetrics
        VStack(spacing: 7) {
            AccountHeader(account: account, date: date)
            Spacer(minLength: 0)
            HStack(spacing: metrics.count == 3 ? 5 : 9) {
                ForEach(metrics) { metric in
                    RingMetric(metric: metric, diameter: metrics.count == 3 ? min(ringDiameter, 44) : ringDiameter)
                }
            }
            Spacer(minLength: 0)
            AccountStatus(account: account)
        }
        .padding(9)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RingMetric: View {
    let metric: WidgetQuotaMetric
    let diameter: CGFloat

    var body: some View {
        Group {
            if metric.window?.wallet != nil || metric.window == nil {
                VStack(spacing: 4) {
                    Text(metric.valueText)
                        .font(.system(size: diameter * 0.2, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                    Text(metric.title)
                        .font(.system(size: 8, weight: .semibold))
                }
                .frame(minHeight: diameter)
            } else {
                VStack(spacing: 3) {
                    QuotaRing(metric: metric, diameter: diameter, lineWidth: max(5, diameter * 0.09))
                        .overlay {
                            Text(percentage)
                                .font(.system(size: diameter * 0.22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                        }
                    Text(metric.title.replacingOccurrences(of: "已用", with: ""))
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(timingText)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) \(metric.valueText)，\(timingText)")
    }

    private var percentage: String {
        if metric.window?.isUnlimited == true { return "∞" }
        guard let window = metric.window,
              let value = QuotaFormatting.effectiveUsedPercentage(window),
              value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private var timingText: String {
        guard let window = metric.window else { return "时间未提供" }
        if let expiresAt = window.expiresAt { return "到期 \(QuotaFormatting.resetDate(expiresAt))" }
        return "重置 \(QuotaFormatting.resetDate(window.resetsAt))"
    }
}

private struct AccountStatus: View {
    let account: WidgetAccountSnapshot

    var body: some View {
        if account.lastFailure != nil {
            Text("刷新失败 · 保留旧数据")
                .font(.system(size: 7))
                .foregroundStyle(.orange)
        } else if account.walletAvailable == false {
            Text("API 不可用")
                .font(.system(size: 7))
                .foregroundStyle(.orange)
        } else if account.quotaExceeded == true {
            Text("额度已用尽")
                .font(.system(size: 7))
                .foregroundStyle(.orange)
        } else if let collectedAt = account.collectedAt {
            Text("更新于 \(collectedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuotaRing: View {
    let metric: WidgetQuotaMetric
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var fraction: CGFloat? {
        metric.ringFraction.map { CGFloat($0) }
    }

    private var tint: Color {
        guard let value = metric.window?.usedPercentage else { return .secondary }
        if value >= 80 { return .red }
        if value >= 50 { return .yellow }
        return .green
    }
}

#if os(iOS)
#Preview("Small", as: .systemSmall) {
    PhoneQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}

#Preview("Medium", as: .systemMedium) {
    PhoneQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .medium)
}

#Preview("Large", as: .systemLarge) {
    PhoneQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .large)
}

#Preview("Lock Screen Circular", as: .accessoryCircular) {
    PhoneQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    PhoneQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}

#Preview("Lock Screen Inline", as: .accessoryInline) {
    PhoneQuotaWidget()
} timeline: {
    WidgetPlaceholder.entry(family: .single)
}
#else
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
