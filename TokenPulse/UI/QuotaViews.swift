import SwiftUI

struct AccountQuotaView: View {
    @Environment(\.editMode) private var editMode
    let state: AccountQuotaState
    let walletCurrency: String?
    let isRefreshing: Bool
    let refresh: () async -> Void
    @State private var isExpanded = false

    var body: some View {
        // Keep the disclosure content inside one List row, including during drag and delete.
        VStack {
            if editMode?.wrappedValue.isEditing == true {
                AccountSummaryView(state: state, walletCurrency: walletCurrency)
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let snapshot = state.snapshot {
                            if let plan = snapshot.subscriptionPlan, state.account.provider == .codex {
                                LabeledContent("套餐", value: plan.displayName)
                            }
                            if let plan = QuotaFormatting.providerPlanName(snapshot.providerPlanName, presentation: snapshot.providerPlanPresentation) {
                                LabeledContent("套餐", value: plan)
                            }
                            if let status = QuotaFormatting.quotaStatus(snapshot.quotaStatusText, provider: state.account.provider) {
                                Text(status).font(.subheadline).foregroundStyle(.secondary)
                            }
                            let detailWindows = snapshot.windows(for: state.account.provider, surface: .detail)
                            ForEach(detailWindows) { window in
                                if window.scope == nil || window.hasDetailValues {
                                    QuotaWindowView(window: window, provider: state.account.provider)
                                } else {
                                    LabeledContent(
                                        L10n.windowDisplayName(window, provider: state.account.provider),
                                        value: QuotaFormatting.usage(window)
                                    )
                                }
                                if window.id != detailWindows.last?.id {
                                    Divider()
                                }
                            }
                            if state.account.provider == .codex {
                                LabeledContent(
                                    "可手动重置",
                                    value: QuotaFormatting.remainingResets(snapshot.remainingResetCount)
                                )
                            }
                            // The collapsed summary above already carries the 余额不足 / 额度已用尽 badge.
                            if let status = QuotaFormatting.walletCollectionStatus(failure: snapshot.walletFailure, collectedAt: snapshot.walletCollectedAt) {
                                Text(status).font(.caption).foregroundStyle(snapshot.walletFailure == nil ? Color.secondary : Color.orange)
                            }
                            Text(L10n.format(snapshot.walletFailure == nil ? "更新于 %@" : "套餐更新于 %@", snapshot.collectedAt.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let failure = state.lastFailure {
                            Label(
                                QuotaFormatting.refreshFailure(failure, hasSnapshot: state.snapshot != nil),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }

                        HStack {
                            Text(L10n.text(isRefreshing ? "正在获取最新额度" : "刷新这个账号"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            AccountRefreshButton(
                                accountName: L10n.demoAccountName(state.account),
                                isRefreshing: isRefreshing,
                                refresh: refresh
                            )
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    AccountSummaryView(state: state, walletCurrency: walletCurrency)
                }
                .disclosureGroupStyle(AccountDisclosureStyle())
            }
        }
    }
}

private struct AccountDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.text(configuration.isExpanded ? "已展开" : "已收起"))

            QuotaDetailsLayout(expansion: configuration.isExpanded ? 1 : 0) {
                configuration.content
            }
            .clipped()
            .opacity(configuration.isExpanded ? 1 : 0)
            .allowsHitTesting(configuration.isExpanded)
            .accessibilityHidden(!configuration.isExpanded)
        }
    }
}

// Report the visible height on each animation frame so List moves the following rows with it.
struct QuotaDetailsLayout: Layout {
    var expansion: CGFloat

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * expansion)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

private struct AccountSummaryView: View {
    let state: AccountQuotaState
    let walletCurrency: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProviderIcon(provider: state.account.provider, size: 24)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.quaternary, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.demoAccountName(state.account))
                        .font(.headline)
                    Text(providerDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state.lastFailure != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("上次刷新失败")
                }
            }

            if let snapshot = state.snapshot {
                Divider()
                if let status = QuotaFormatting.quotaStatus(snapshot.quotaStatusText, provider: state.account.provider) {
                    Text(status).font(.subheadline).foregroundStyle(.secondary)
                } else if snapshot.isNoPlan == true {
                    Text("当前按量计费，没有套餐或 Key 用量上限").font(.subheadline).foregroundStyle(.secondary)
                }
                if state.account.provider == .v0, !snapshot.windows.contains(where: { $0.id == "v0.billing" }) {
                    Text("账期 credits：未提供").font(.caption).foregroundStyle(.secondary)
                }
                if state.account.provider == .v0, !snapshot.windows.contains(where: { $0.id == "v0.rate_limit" }) {
                    Text("消息限流：未提供").font(.caption).foregroundStyle(.secondary)
                }
                let summaryWindows = snapshot.windows(for: state.account.provider, surface: .summary)
                if state.account.provider.balancePresentation == .walletOnly &&
                    (state.account.provider != .newAPI || summaryWindows.contains(where: { $0.wallet?.isMonetary == true })) {
                    if let currency = selectedWalletCurrency(in: summaryWindows),
                       let window = summaryWindows.first(where: { $0.wallet?.currency == currency }) {
                        CompactQuotaWindowView(window: window, provider: state.account.provider)
                    } else if let currency = walletCurrency {
                        Text(L10n.format("所选币种 %@ 未提供", currency))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未返回钱包余额")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if snapshot.walletAvailable == false {
                        Label(QuotaFormatting.walletUnavailableBadge, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    ForEach(summaryWindows) { window in
                        CompactQuotaWindowView(window: window, provider: state.account.provider)
                    }
                }
                if let status = QuotaFormatting.walletCollectionStatus(failure: snapshot.walletFailure, collectedAt: snapshot.walletCollectedAt) {
                    Text(status).font(.caption).foregroundStyle(snapshot.walletFailure == nil ? Color.secondary : Color.orange)
                }
                if snapshot.quotaExceeded == true {
                    Label(QuotaFormatting.quotaExceededBadge, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Label("尚无额度数据", systemImage: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private var providerDescription: String {
        if let snapshot = state.snapshot, let plan = QuotaFormatting.providerPlanName(snapshot.providerPlanName, presentation: snapshot.providerPlanPresentation) { return L10n.format("%@ · %@", state.account.provider.displayName, plan) }
        guard state.account.provider == .codex,
              let plan = state.snapshot?.subscriptionPlan else { return L10n.text(state.account.provider.displayName) }
        return L10n.format("%@ · %@", state.account.provider.displayName, plan.displayName)
    }

    private func selectedWalletCurrency(in windows: [QuotaWindow]) -> String? {
        let wallets = windows.compactMap(\.wallet)
        // A prior USD reminder selection cannot hide the service-selected DIEM
        // reading. Missing monetary selections still remain visibly missing.
        if !wallets.contains(where: \.isMonetary) { return wallets.first?.currency }
        return walletCurrency ?? wallets.first?.currency
    }
}

private struct CompactQuotaWindowView: View {
    let window: QuotaWindow
    var provider: Provider? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                Text(usedValue)
                    .bold()
                    .monospacedDigit()
            } label: {
                Text(L10n.windowDisplayName(window, provider: provider))
                    .font(.subheadline)
            }
            if window.wallet == nil {
                LabeledContent(
                    QuotaFormatting.nextEventLabel(window),
                    value: QuotaFormatting.nextEventValue(window)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var usedValue: String {
        if let wallet = window.wallet {
            return QuotaFormatting.balance(wallet.total, wallet: wallet)
        }
        return QuotaFormatting.usage(window)
    }
}

private struct AccountRefreshButton: View {
    let accountName: String
    let isRefreshing: Bool
    let refresh: () async -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                button.buttonStyle(.glass)
            } else {
                button.buttonStyle(.borderless)
            }
        }
        .disabled(isRefreshing)
        .accessibilityLabel(L10n.format("刷新 %@", accountName))
    }

    private var button: some View {
        Button {
            Task { await refresh() }
        } label: {
            if isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .frame(width: 44, height: 44)
    }
}

struct QuotaWindowView: View {
    let window: QuotaWindow
    var provider: Provider? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format("%@详情", L10n.windowName(window, provider: provider)))
                .font(.subheadline)
                .bold()

            if window.isUnlimited || window.overagePermitted == true || window.isExhausted == true {
                LabeledContent("状态", value: QuotaFormatting.usage(window))
            }
            if let scope = L10n.windowScope(window) {
                LabeledContent("范围", value: scope)
            }

            if let wallet = window.wallet {
                WalletBalanceView(balance: wallet)
            } else if let percentage = QuotaFormatting.effectiveUsedPercentage(window) {
                ProgressView(value: min(max(percentage, 0), 100), total: 100)
                    .accessibilityLabel(L10n.format("%@已用额度", L10n.windowName(window, provider: provider)))
                    .accessibilityValue(QuotaFormatting.percentage(percentage))
            }

            if !window.isUnlimited, let counts = window.exactCounts {
                if let used = counts.used { LabeledContent("已用", value: QuotaFormatting.count(used, window: window)) }
                if let remaining = counts.remaining { LabeledContent("剩余", value: QuotaFormatting.count(remaining, window: window)) }
                if let total = counts.total { LabeledContent(QuotaFormatting.totalLabel(window), value: QuotaFormatting.count(total, window: window)) }
            } else if !window.isUnlimited, let remaining = window.remainingCount {
                LabeledContent("剩余", value: remainingValue(remaining))
            } else if !window.isUnlimited, let total = window.totalCount {
                LabeledContent("总量", value: QuotaFormatting.count(total, window: window))
            }

            if let expiresAt = window.expiresAt {
                LabeledContent(L10n.text(window.id == "stepfun.credits" ? "最早积分到期" : "到期时间"),
                               value: QuotaFormatting.resetDate(expiresAt))
            }
            if window.resetsAt != nil {
                LabeledContent("下次重置", value: QuotaFormatting.resetDate(window.resetsAt, precision: window.resetDatePrecision))
            }
            if let replenishment = window.nextReplenishmentAt {
                LabeledContent("下次补充", value: QuotaFormatting.resetDate(replenishment))
            }
            if window.expiresAt == nil || window.resetsAt != nil {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if window.needsUpdate(at: context.date) {
                        Label("已到预计重置时间，等待刷新确认", systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func remainingValue(_ remaining: Double) -> String {
        guard let total = window.totalCount else { return QuotaFormatting.count(remaining, window: window) }
        let values = "\(QuotaFormatting.count(remaining, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2)) / \(QuotaFormatting.count(total, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2))"
        return QuotaFormatting.withUnit(values, unit: L10n.windowUnit(window))
    }
}

struct WalletBalanceView: View {
    let balance: WalletBalance

    var body: some View {
        LabeledContent(balance.isMonetary ? L10n.text("总可用余额") : L10n.format("剩余 %@", QuotaFormatting.balanceUnit(balance)),
                       value: QuotaFormatting.balance(balance.total, wallet: balance))
        if balance.isMonetary {
            LabeledContent("赠送余额", value: QuotaFormatting.balance(balance.granted, wallet: balance))
            LabeledContent("充值余额", value: QuotaFormatting.balance(balance.toppedUp, wallet: balance))
        }
    }
}
