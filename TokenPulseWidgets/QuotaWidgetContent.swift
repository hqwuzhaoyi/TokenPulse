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

#if !TOKENPULSE_APP
struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<QuotaWidgetIntent>] {
        [AppIntentRecommendation(intent: QuotaWidgetIntent(), description: L10n.text("选择 TokenPulse 账号"))]
    }

    func placeholder(in context: Context) -> QuotaWidgetEntry {
        WidgetPlaceholder.entry(family: presentationFamily(context.family))
    }

    func snapshot(for configuration: QuotaWidgetIntent, in context: Context) async -> QuotaWidgetEntry {
        await entry(for: configuration, family: presentationFamily(context.family), invocation: "phone.snapshot")
    }

    func timeline(for configuration: QuotaWidgetIntent, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        let entry = await entry(for: configuration, family: presentationFamily(context.family), invocation: "phone.timeline")
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
        family: WidgetPresentationFamily,
        invocation: String
    ) async -> QuotaWidgetEntry {
        #if DEBUG
        if let fixture = WidgetDebugFixture.requestedEntry(family: family, invocation: invocation) {
            return fixture
        }
        #endif
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
        [AppIntentRecommendation(intent: WatchQuotaWidgetIntent(), description: L10n.text("选择 TokenPulse 账号"))]
    }

    func placeholder(in context: Context) -> QuotaWidgetEntry {
        WidgetPlaceholder.entry(family: .single)
    }

    func snapshot(for configuration: WatchQuotaWidgetIntent, in context: Context) async -> QuotaWidgetEntry {
        await entry(for: configuration, invocation: "watch.snapshot")
    }

    func timeline(for configuration: WatchQuotaWidgetIntent, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        let entry = await entry(for: configuration, invocation: "watch.timeline")
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

    private func entry(for configuration: WatchQuotaWidgetIntent, invocation: String) async -> QuotaWidgetEntry {
        #if DEBUG
        if let fixture = WidgetDebugFixture.requestedEntry(family: .single, invocation: invocation) { return fixture }
        #endif
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

#endif

enum WidgetPlaceholder {
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
                name: L10n.text("MiniMax 国内"), provider: .miniMaxChina,
                windows: [window(id: "minimax.five", name: "5 小时额度", period: .fiveHour,
                                 used: 46, reset: date.addingTimeInterval(2 * 3_600))]
            ),
            snapshot(
                name: L10n.text("GLM 工作号"), provider: .zai,
                windows: [
                    window(id: "glm.weekly", name: "每周额度", period: .weekly,
                           used: 38, reset: date.addingTimeInterval(3 * 86_400)),
                    window(id: "glm.five", name: "5 小时额度", period: .fiveHour,
                           used: 71, reset: date.addingTimeInterval(58 * 60)),
                ]
            ),
            snapshot(
                name: L10n.text("Codex 团队号"), provider: .codex,
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
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: QuotaWidgetEntry
    #if DEBUG
    private let familyOverride: WidgetFamily?

    init(entry: QuotaWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }
    #endif

    private var family: WidgetFamily {
        #if DEBUG
        familyOverride ?? environmentFamily
        #else
        environmentFamily
        #endif
    }

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
            watchSmall(entry.accounts[0])
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
                homeScreenSmall(entry.accounts[0])
            }
        }
        #endif
    }

    #if os(watchOS)
    @ViewBuilder
    private func accessoryCorner(_ account: WidgetAccountSnapshot) -> some View {
        if let metric = account.displayMetrics.first {
            Text(metric.valueText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .widgetLabel {
                    if let fraction = metric.ringFraction {
                        Gauge(value: fraction) {
                            Text(WidgetContentPresentation.resetText(metric))
                        } currentValueLabel: {
                            Text(metric.valueText)
                        }
                    } else {
                        Text(L10n.format("%@ %@", metric.title, metric.valueText))
                    }
                }
                .overlay(alignment: .topTrailing) { compactStateIcon(account) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary(account))
        } else {
            ProviderIcon(provider: account.account.provider, size: 20)
                .widgetLabel("额度未提供")
                .accessibilityLabel(WidgetContentPresentation.accessibilitySummary(account, at: entry.date))
        }
    }
    #endif

    private func inline(_ account: WidgetAccountSnapshot) -> some View {
        let values = account.ringMetrics.map { L10n.format("%@ %@", $0.displayTitle, $0.valueText) }
            .joined(separator: " · ")
        let name = WidgetContentPresentation.accountName(account.account)
        let fullText = L10n.format("%@ %@%@%@", name, values, resetCountSuffix(account), inlineStatusSuffix(account))
        return ViewThatFits(in: .horizontal) {
            Text(fullText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(L10n.format("%@ %@", name, WidgetContentPresentation.compactInlineDetails(account, at: entry.date)))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(WidgetContentPresentation.compactInlineDetails(account, at: entry.date))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetContentPresentation.accessibilitySummary(account, at: entry.date))
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
            .overlay(alignment: .topTrailing) { compactStateIcon(account) }
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
            .overlay(alignment: .topTrailing) { compactStateIcon(account) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(account))
        }
    }

    @ViewBuilder
    private func compactStateIcon(_ account: WidgetAccountSnapshot) -> some View {
        if account.lastFailure != nil || account.walletFailure != nil || account.walletAvailable == false || account.quotaExceeded == true {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 8)).foregroundStyle(.orange).accessibilityHidden(true)
        } else if account.needsUpdate(at: entry.date) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 8)).accessibilityHidden(true)
        }
    }

    private func accessoryRectangular(_ account: WidgetAccountSnapshot) -> some View {
        HStack(spacing: 8) {
            if let metric = account.displayMetrics.first {
                if metric.window != nil, metric.window?.wallet == nil {
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
                    Text(WidgetContentPresentation.accountName(account.account))
                        .font(.caption2.bold()).lineLimit(1)
                        .minimumScaleFactor(0.6).allowsTightening(true)
                }
                if let metric = account.displayMetrics.first {
                    if metric.window?.wallet != nil || metric.window == nil {
                        Text(metric.valueText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit().lineLimit(1)
                            .minimumScaleFactor(0.5).allowsTightening(true)
                            .layoutPriority(1)
                        Text(metric.displayTitle)
                            .font(.caption2).lineLimit(1)
                            .minimumScaleFactor(0.65).allowsTightening(true)
                        if let status = WidgetContentPresentation.status(account) {
                            Text(status)
                                .font(.system(size: 8)).foregroundStyle(.white.opacity(0.65))
                                .lineLimit(2).minimumScaleFactor(0.65).allowsTightening(true)
                        }
                    } else if let status = metric.statusText {
                        Text(status).font(.caption2).lineLimit(2)
                    } else {
                        Text(metric.title).font(.caption2).lineLimit(1)
                            .minimumScaleFactor(0.65).allowsTightening(true)
                        Text(account.lastFailure != nil || account.walletFailure != nil
                             ? WidgetContentPresentation.status(account) ?? resetText(metric)
                             : account.needsUpdate(at: entry.date) ? L10n.text("待更新") : resetText(metric))
                            .font(.system(size: 8)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(account))
    }

    private func watchSmall(_ account: WidgetAccountSnapshot) -> some View {
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

    private func homeScreenSmall(_ account: WidgetAccountSnapshot) -> some View {
        HomeScreenAccountContent(account: account, date: entry.date)
    }

    private var medium: some View {
        let accounts = Array(entry.accounts.prefix(2))
        return HStack(spacing: 0) {
            ForEach(accounts.indices, id: \.self) { index in
                let account = accounts[index]
                accountLink(account) {
                    MediumAccountColumn(account: account, date: entry.date)
                }
                if index < accounts.count - 1 {
                    Divider().overlay(.white.opacity(0.12))
                }
            }
        }
    }

    private var large: some View {
        let accounts = Array(entry.accounts.prefix(4))
        return VStack(spacing: 0) {
            ForEach(accounts.indices, id: \.self) { index in
                let account = accounts[index]
                VStack(spacing: 0) {
                    accountLink(account) {
                        LargeAccountRow(account: account, date: entry.date)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    if index < accounts.count - 1 {
                        Divider().overlay(.white.opacity(0.12))
                    }
                }
            }
            if entry.accountSelectionMissing {
                Text("部分账号尚未同步")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
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
        WidgetContentPresentation.emptyMessage(selectionRequired: entry.selectionRequired,
                                               accountSelectionMissing: entry.accountSelectionMissing,
                                               hasAvailableAccounts: entry.hasAvailableAccounts)
    }

    private func accountURL(_ account: WidgetAccountSnapshot) -> URL? {
        PlatformConstants.accountDeepLink(for: account.id)
    }

    private func resetCountSuffix(_ account: WidgetAccountSnapshot) -> String {
        guard account.supportsManualResetCount else { return "" }
        return WidgetContentPresentation.resetCount(account).map { L10n.format(" · %@", $0) } ?? ""
    }

    private func resetText(_ metric: WidgetQuotaMetric) -> String {
        WidgetContentPresentation.resetText(metric)
    }

    private func accessibilitySummary(_ account: WidgetAccountSnapshot) -> String {
        WidgetContentPresentation.accessibilitySummary(account, at: entry.date)
    }

    private func inlineStatusSuffix(_ account: WidgetAccountSnapshot) -> String {
        if account.lastFailure != nil || account.walletFailure != nil {
            return WidgetContentPresentation.status(account).map { L10n.format(" · %@", $0) } ?? ""
        }
        if account.needsUpdate(at: entry.date) { return L10n.format(" · %@", L10n.text("待更新")) }
        return availabilitySuffix(account)
    }

    private func availabilitySuffix(_ account: WidgetAccountSnapshot) -> String {
        WidgetContentPresentation.availability(account).map { L10n.format(" · %@", $0) } ?? ""
    }

}

private struct AccountHeader: View {
    let account: WidgetAccountSnapshot
    let date: Date
    var showsResetCount = true

    var body: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: account.account.provider, size: 14)
            Text(WidgetContentPresentation.accountName(account.account)).font(.caption.bold()).lineLimit(1)
            Spacer(minLength: 0)
            if showsResetCount && account.supportsManualResetCount {
                Text(WidgetContentPresentation.resetCount(account) ?? "")
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
                    .accessibilityLabel(account.walletAvailable == false
                        ? QuotaFormatting.walletUnavailableBadge
                        : QuotaFormatting.quotaExceededBadge)
            }
            if account.needsUpdate(at: date) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .accessibilityLabel("待更新")
            }
        }
    }
}

private struct MediumAccountColumn: View {
    let account: WidgetAccountSnapshot
    let date: Date

    var body: some View {
        let metrics = account.displayMetrics
        VStack(alignment: .leading, spacing: 2) {
            AccountHeader(account: account, date: date, showsResetCount: false)
            if metrics.isEmpty {
                Text("额度未提供")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                ForEach(metrics) { metric in
                    HorizontalMetric(metric: metric, metricCount: metrics.count, presentation: .mediumPanel)
                }
            }
            Spacer(minLength: 0)
            HomeScreenAccountFooter(account: account)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LargeAccountRow: View {
    let account: WidgetAccountSnapshot
    let date: Date

    var body: some View {
        let metrics = account.displayMetrics
        VStack(alignment: .leading, spacing: 3) {
            header
            if metrics.isEmpty {
                Text("额度未提供")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(metrics) { metric in
                        HorizontalMetric(metric: metric, metricCount: metrics.count, presentation: .largePanel)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            ProviderIcon(provider: account.account.provider, size: 13)
            Text(WidgetContentPresentation.accountName(account.account))
                .font(.caption.bold())
                .lineLimit(1)
            if account.supportsManualResetCount {
                Text(WidgetContentPresentation.resetCount(account) ?? "")
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
            }
            if account.needsUpdate(at: date) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .accessibilityLabel("待更新")
            }
            Spacer(minLength: 4)
            AccountStatus(account: account, fontSize: 8)
                .lineLimit(1)
        }
    }
}

private enum HorizontalMetricPresentation {
    case homeScreenSmall
    case mediumPanel
    case largePanel
}

private struct HomeScreenAccountContent: View {
    let account: WidgetAccountSnapshot
    let date: Date

    var body: some View {
        let metrics = account.displayMetrics
        VStack(spacing: metrics.count >= 2 ? 2 : 4) {
            AccountHeader(account: account, date: date, showsResetCount: false)
            if metrics.isEmpty {
                Spacer(minLength: 0)
                Text("额度未提供")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
            } else {
                if metrics.count == 1 { Spacer(minLength: 4) }
                ForEach(metrics) { metric in
                    HorizontalMetric(metric: metric, metricCount: metrics.count)
                }
                Spacer(minLength: 0)
            }
            HomeScreenAccountFooter(account: account)
        }
    }
}

private struct HomeScreenAccountFooter: View {
    let account: WidgetAccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if account.supportsManualResetCount {
                Text(WidgetContentPresentation.resetCount(account) ?? "")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            }
            AccountStatus(account: account, fontSize: 9)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct HorizontalMetric: View {
    let metric: WidgetQuotaMetric
    let metricCount: Int
    var presentation: HorizontalMetricPresentation = .homeScreenSmall

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .homeScreenSmall:
            homeScreenSmall
        case .mediumPanel:
            mediumPanel
        case .largePanel:
            largePanel
        }
    }

    private var homeScreenSmall: some View {
        VStack(alignment: .leading, spacing: metricCount >= 3 || hasCountValue ? 1 : 3) {
            if metric.window?.wallet != nil {
                Text(metric.displayTitle)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .lineLimit(2)
                Text(valueText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .layoutPriority(1)
            } else if metric.window?.isExhausted == true {
                Text(metric.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                Text(valueText)
                    .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .layoutPriority(1)
            } else if hasCountValue {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .lineLimit(2)
                    Spacer(minLength: 2)
                    if metric.ringFraction != nil {
                        Text(percentageText)
                            .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    Text(valueText)
                        .font(.system(size: metricCount == 1 ? 16 : 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .lineLimit(2)
                    Spacer(minLength: 2)
                    Text(valueText)
                        .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .layoutPriority(1)
                }
            }
            progress
            if metric.window != nil, metric.window?.wallet == nil {
                Text(compactTimingText)
                    .font(.system(size: timingFontSize))
                    .foregroundStyle(.white.opacity(0.65))
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .lineLimit(metricCount >= 3 ? 1 : 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var mediumPanel: some View {
        VStack(alignment: .leading, spacing: 1) {
            if hasCountValue {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    panelTitle
                    Spacer(minLength: 2)
                    Text(percentageText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    panelValue(fontSize: 12)
                    Spacer(minLength: 2)
                    panelTiming
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    panelTitle
                    Spacer(minLength: 2)
                    panelValue(fontSize: 14)
                }
            }
            progress
            if !hasCountValue, metric.window != nil, metric.window?.wallet == nil {
                panelTiming
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var largePanel: some View {
        VStack(alignment: .leading, spacing: 1) {
            panelTitle
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                panelValue(fontSize: 15)
                if hasCountValue, metric.ringFraction != nil {
                    Spacer(minLength: 1)
                    Text(percentageText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            progress
            if metric.window != nil, metric.window?.wallet == nil {
                panelTiming
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var panelTitle: some View {
        Text(metric.displayTitle)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func panelValue(fontSize: CGFloat) -> some View {
        Text(valueText)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    @ViewBuilder
    private var progress: some View {
        if let fraction = metric.ringFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private var panelTiming: some View {
        Text(compactTimingText)
            .font(.system(size: 8))
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var valueText: String {
        guard let window = metric.window,
              ["qoder.userQuota", "qoder.orgResourcePackage"].contains(window.id),
              let unit = window.unit, unit.lowercased() == "credits",
              metric.valueText.hasSuffix(" " + unit) else { return metric.valueText }
        return String(metric.valueText.dropLast(unit.count + 1))
    }

    private var accessibilityText: String {
        WidgetContentPresentation.metricSummary(metric,
            percentage: hasCountValue && metric.ringFraction != nil ? percentageText : nil)
    }

    private var titleFontSize: CGFloat {
        metricCount == 1 ? 13 : metricCount == 2 ? 12 : 11
    }

    private var valueFontSize: CGFloat {
        metricCount == 1 ? 22 : metricCount == 2 ? 16 : 13
    }

    private var timingFontSize: CGFloat {
        metricCount == 1 ? 11 : metricCount == 2 ? 10 : 9
    }

    private var hasCountValue: Bool {
        guard let window = metric.window else { return false }
        return QuotaFormatting.exactCountSummary(window) != nil || window.unit != nil && (window.remainingCount != nil || window.totalCount != nil)
    }

    private var percentageText: String {
        guard let window = metric.window,
              let value = QuotaFormatting.effectiveUsedPercentage(window),
              value.isFinite else { return "" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }

    private var timingText: String {
        return WidgetContentPresentation.resetText(metric)
    }

    private var compactTimingText: String {
        guard let window = metric.window else { return L10n.text("时间未提供") }
        guard let date = QuotaFormatting.nextEventDate(window) else {
            if window.resetSemantics == .continuousReplenishment { return L10n.text("持续补充") }
            return WidgetContentPresentation.resetText(metric)
        }
        if window.resetDatePrecision == .day, date == window.resetsAt {
            return WidgetContentPresentation.resetText(metric)
        }
        return L10n.format("%@ %@", QuotaFormatting.nextEventLabel(window), compactDate(date))
    }

    private func compactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        let includesYear = !Calendar.autoupdatingCurrent.isDate(date, equalTo: Date(), toGranularity: .year)
        formatter.setLocalizedDateFormatFromTemplate(includesYear ? "yMdjm" : "Mdjm")
        return formatter.string(from: date)
    }

    private var tint: Color {
        guard let value = metric.window?.usedPercentage else { return .secondary }
        if value >= 80 { return .red }
        if value >= 50 { return .yellow }
        return .green
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
                    Text(metric.title)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(timingText)
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetContentPresentation.metricSummary(metric))
    }

    private var percentage: String {
        if let window = metric.window, QuotaFormatting.overageDescription(window) != nil { return L10n.text("付费") }
        if metric.window?.isUnlimited == true { return "∞" }
        guard let window = metric.window,
              let value = QuotaFormatting.effectiveUsedPercentage(window),
              value.isFinite else { return "—" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private var timingText: String {
        return WidgetContentPresentation.resetText(metric)
    }
}

private struct AccountStatus: View {
    let account: WidgetAccountSnapshot
    var fontSize: CGFloat = 7

    var body: some View {
        if let status = WidgetContentPresentation.status(account) {
            Text(status)
                .font(.system(size: fontSize))
                .foregroundStyle(account.lastFailure != nil || account.walletFailure != nil || account.walletAvailable == false || account.quotaExceeded == true ? Color.orange : Color.white.opacity(0.65))
        }
        if let status = QuotaFormatting.quotaStatus(account.quotaStatusText, provider: account.account.provider) {
            Text(status).font(.system(size: fontSize)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
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


#if DEBUG
/// Activated only by a debug harness writing the shared suite. There is no product UI.
/// The same entry reaches the real extension timeline and the exported QuotaWidgetView renderer.
enum WidgetDebugFixture {
    static let requestKey = "debug.widget.fixture"

    static func requestedEntry(family: WidgetPresentationFamily, invocation: String) -> QuotaWidgetEntry? {
        guard let defaults = UserDefaults(suiteName: PlatformConstants.appGroupIdentifier),
              let scenario = defaults.string(forKey: requestKey), supportedScenarios.contains(scenario) else { return nil }
        let entry = entry(scenario: scenario, family: family)
        // Written by the extension's own process, using its Bundle.main and native catalog.
        let evidence: [String: Any] = [
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "bundleName": Bundle.main.bundleURL.lastPathComponent,
            "preferredLocalizations": Bundle.main.preferredLocalizations,
            "scenario": scenario,
            "providerInvocation": invocation,
            "isWidgetExtension": Bundle.main.bundleURL.pathExtension == "appex",
            "expectedLanguage": defaults.string(forKey: "debug.widget.expectedLanguage") ?? "",
            "emptyMessage": WidgetContentPresentation.emptyMessage(selectionRequired: true, accountSelectionMissing: false, hasAvailableAccounts: false),
            "summaries": entry.accounts.map { WidgetContentPresentation.accessibilitySummary($0, at: entry.date) },
            "timestamp": Date().timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]) {
            defaults.set(data, forKey: "debug.widget.runtime.\(Bundle.main.bundleIdentifier ?? "unknown")")
            defaults.synchronize()
        }
        return entry
    }

    static let supportedScenarios: Set<String> = [
        "quota", "wallet", "empty", "unselected", "missing", "stale", "replenishment", "dateOnly", "longName", "exhausted"
    ]

    static func entry(scenario: String, family: WidgetPresentationFamily, date: Date = Date()) -> QuotaWidgetEntry {
        if ["empty", "unselected", "missing"].contains(scenario) {
            return QuotaWidgetEntry(date: date, accounts: [], selectionRequired: scenario != "missing",
                                    accountSelectionMissing: scenario == "missing", hasAvailableAccounts: scenario != "empty")
        }
        let provider: Provider = scenario == "wallet" ? .deepSeek : .codex
        let window: QuotaWindow
        if scenario == "wallet" {
            let windowID: String = "deepseek.wallet.USD"
            let windowName: String = "API 钱包余额"
            let total: Decimal = Decimal(string: "1234.567890123456789")!
            let wallet: WalletBalance = WalletBalance(currency: "USD", total: total)
            window = QuotaWindow(id: windowID, name: windowName, scope: nil,
                                 usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                 wallet: wallet)
        } else {
            let windowID: String = "codex.weekly"
            let windowName: String = "每周额度"
            let isExhausted: Bool = scenario == "exhausted"
            let resetsAt: Date?
            if scenario == "replenishment" {
                resetsAt = nil
            } else if scenario == "stale" {
                resetsAt = date.addingTimeInterval(-60)
            } else {
                resetsAt = date.addingTimeInterval(3 * 86_400)
            }
            let resetSemantics: QuotaResetSemantics? = scenario == "replenishment" ? .continuousReplenishment : nil
            let resetDatePrecision: QuotaDatePrecision? = scenario == "dateOnly" ? .day : nil
            window = QuotaWindow(id: windowID, name: windowName, scope: nil, period: .weekly,
                                 isExhausted: isExhausted, usedPercentage: 63,
                                 remainingCount: nil, totalCount: nil, resetsAt: resetsAt,
                                 resetSemantics: resetSemantics, resetDatePrecision: resetDatePrecision)
        }
        let collectedAt: Date = date.addingTimeInterval(-600)
        let lastFailure: RefreshFailure? = scenario == "stale" ? .network : nil
        let accounts: [WidgetAccountSnapshot] = (0..<family.accountLimit).map { index -> WidgetAccountSnapshot in
            let identifier: String = String(format: "09000000-0000-0000-0000-%012d", index + 1)
            let accountID: UUID = UUID(uuidString: identifier)!
            let name: String = scenario == "longName"
                ? "我的研发账号 · Very Long Research Account 🌙 \(index + 1)" : "Fixture \(index + 1)"
            let account: SubscriptionAccount = SubscriptionAccount(id: accountID, name: name, provider: provider)
            let remainingResetCount: Int = index == 0 ? 1 : index == 1 ? 0 : 3
            return WidgetAccountSnapshot(account: account, windows: [window], collectedAt: collectedAt,
                                         lastFailure: lastFailure, remainingResetCount: remainingResetCount,
                                         subscriptionPlan: .pro)
        }
        return QuotaWidgetEntry(date: date, accounts: accounts, selectionRequired: false,
                                accountSelectionMissing: false, hasAvailableAccounts: true)
    }
}
#endif
