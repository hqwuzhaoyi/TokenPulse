import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var monitor: QuotaMonitor
    @ObservedObject var runtime: AppRuntime
    @State private var showingAddAccount = false
    @State private var accountsToDelete: [SubscriptionAccount] = []
    @State private var linkedAccount: UUID?
    @State private var selectedTab = AppTab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if monitor.states.isEmpty {
                        ContentUnavailableView {
                            Label("添加服务账号", systemImage: "waveform.path.ecg")
                        } description: {
                            Text("集中查看 AI 服务的套餐额度与 API 钱包余额。")
                        } actions: {
                            AddAccountButton { showingAddAccount = true }
                            if !runtime.isDemoMode {
                                Button("体验演示 / Try Demo") {
                                    Task { await runtime.setDemoMode(true) }
                                }
                                .disabled(runtime.isSwitchingMode)
                            }
                            if monitor.hasPendingCredentialCleanup {
                                Button("重试凭证清理") { Task { await monitor.retryPendingCredentialCleanup() } }
                            }
                        }
                    } else {
                        List {
                            if monitor.hasPendingCredentialCleanup {
                                Section {
                                    Button("重试凭证清理", systemImage: "arrow.clockwise.circle") {
                                        Task { await monitor.retryPendingCredentialCleanup() }
                                    }
                                } footer: {
                                    Text("已移除账号的凭证未能清理，请重试。")
                                }
                            }
                            Section {
                                ForEach(monitor.states) { state in
                                    AccountQuotaView(
                                        state: state,
                                        walletCurrency: monitor.configuration(for: state.id)?.reminders.walletCurrency,
                                        isRefreshing: monitor.refreshingAccountIDs.contains(state.id),
                                        refresh: { await monitor.refresh(accountID: state.id) }
                                    )
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("删除", systemImage: "trash") {
                                            accountsToDelete = [state.account]
                                        }
                                        .tint(.red)
                                    }
                                }
                                .onMove { from, to in
                                    monitor.reorderAccounts(from: from, to: to)
                                    Task { await monitor.persistAccountOrder() }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .listRowSpacing(16)
                        .contentMargins(.top, 8, for: .scrollContent)
                        .refreshable { await monitor.refreshAll() }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if runtime.isDemoMode {
                        HStack {
                            Label("演示模式 · 示例数据", systemImage: "play.circle")
                                .font(.caption)
                            Spacer()
                            Button("退出演示") { Task { await runtime.setDemoMode(false) } }
                                .font(.caption.bold())
                                .disabled(runtime.isSwitchingMode)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加账号", systemImage: "plus") { showingAddAccount = true }
                    }
                }
                .sheet(isPresented: $showingAddAccount) {
                    AddAccountView(isDemoMode: runtime.isDemoMode) { name, key, provider, accountID in
                        let previousCount = monitor.states.count
                        await monitor.addAccount(name: name, credential: key, provider: provider, accountID: accountID)
                        return monitor.states.count > previousCount
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .tabItem {
                Label("主屏幕", systemImage: "house")
            }
            .tag(AppTab.home)

            AccountSettingsView(monitor: monitor, runtime: runtime, initialAccountID: linkedAccount)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .disabled(runtime.isSwitchingMode)
        .overlay {
            if runtime.isSwitchingMode { ProgressView("正在切换模式") }
        }
        .confirmationDialog("删除账号？", isPresented: Binding(
            get: { !accountsToDelete.isEmpty },
            set: { if !$0 { accountsToDelete = [] } }
        ), titleVisibility: .visible) {
            Button("删除账号", role: .destructive) {
                let accountIDs = accountsToDelete.map(\.id)
                accountsToDelete = []
                Task { for id in accountIDs { await monitor.deleteAccount(accountID: id) } }
            }
            Button("取消", role: .cancel) { accountsToDelete = [] }
        } message: {
            Text(runtime.isDemoMode
                 ? "将移除选中的演示账号及其示例数据。真实账号不受影响。"
                 : "将移除“\(accountsToDelete.map(\.name).joined(separator: "、"))”的凭证、额度数据和提醒；开启 iCloud 同步后也会从其他设备移除。")
        }
        .alert("本地存储错误", isPresented: Binding(
            get: { monitor.storageMessage != nil },
            set: { if !$0 { monitor.dismissStorageMessage() } }
        )) {
            Button("好") { monitor.dismissStorageMessage() }
        } message: {
            Text(monitor.storageMessage ?? "")
        }
        .onOpenURL { url in
            guard url.scheme == PlatformConstants.accountDeepLinkScheme else { return }
            if url.host == "account", let id = UUID(uuidString: url.lastPathComponent) {
                linkedAccount = id
                selectedTab = .settings
            } else if url.host == "accounts" {
                linkedAccount = nil
                selectedTab = .home
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await monitor.applicationDidBecomeActive() }
        }
    }
}

private enum AppTab: Hashable {
    case home
    case settings
}

private struct AddAccountButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button("添加账号", systemImage: "plus", action: action)
                .buttonStyle(.glassProminent)
        } else {
            Button("添加账号", systemImage: "plus", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct AccountQuotaView: View {
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
                            if let plan = snapshot.providerPlanName {
                                LabeledContent("套餐", value: plan)
                            }
                            let detailWindows = snapshot.windows(for: state.account.provider, surface: .detail)
                            ForEach(detailWindows) { window in
                                if window.scope == nil || state.account.provider == .qoderInternational {
                                    QuotaWindowView(window: window)
                                } else {
                                    LabeledContent(
                                        window.displayName,
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
                            Text("更新于 \(snapshot.collectedAt.formatted(date: .abbreviated, time: .shortened))")
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
                            Text(isRefreshing ? "正在获取最新额度" : "刷新这个账号")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            AccountRefreshButton(
                                accountName: state.account.name,
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
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")

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
                    Text(state.account.name)
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
                let summaryWindows = snapshot.windows(for: state.account.provider, surface: .summary)
                if state.account.provider.hasMonetaryWallet &&
                    (state.account.provider != .newAPI || summaryWindows.contains(where: { $0.wallet?.isMonetary == true })) {
                    if let currency = selectedWalletCurrency(in: summaryWindows),
                       let window = summaryWindows.first(where: { $0.wallet?.currency == currency }) {
                        CompactQuotaWindowView(window: window)
                    } else if let currency = walletCurrency {
                        Text("所选币种 \(currency) 未提供")
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
                        CompactQuotaWindowView(window: window)
                    }
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
        if let plan = state.snapshot?.providerPlanName { return "\(state.account.provider.displayName) · \(plan)" }
        guard state.account.provider == .codex,
              let plan = state.snapshot?.subscriptionPlan else { return state.account.provider.displayName }
        return "\(state.account.provider.displayName) · \(plan.displayName)"
    }

    private func selectedWalletCurrency(in windows: [QuotaWindow]) -> String? {
        walletCurrency ?? windows.compactMap(\.wallet?.currency).first
    }
}

private struct CompactQuotaWindowView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                Text(usedValue)
                    .bold()
                    .monospacedDigit()
            } label: {
                Text(window.displayName)
                    .font(.subheadline)
            }
            if window.wallet == nil {
                LabeledContent(
                    QuotaFormatting.nextEventLabel(window),
                    value: QuotaFormatting.resetDate(QuotaFormatting.nextEventDate(window))
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
        .accessibilityLabel("刷新 \(accountName)")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(window.name)详情")
                .font(.subheadline)
                .bold()

            if window.isUnlimited || window.overagePermitted == true || window.isExhausted == true {
                LabeledContent("状态", value: QuotaFormatting.usage(window))
            }
            if let scope = window.scope {
                LabeledContent("范围", value: scope)
            }

            if let wallet = window.wallet {
                WalletBalanceView(balance: wallet)
            } else if let percentage = QuotaFormatting.effectiveUsedPercentage(window) {
                ProgressView(value: min(max(percentage, 0), 100), total: 100)
                    .accessibilityLabel("\(window.name)已用额度")
                    .accessibilityValue(QuotaFormatting.percentage(percentage))
            }

            if !window.isUnlimited, let remaining = window.remainingCount {
                LabeledContent("剩余", value: remainingValue(remaining))
            } else if !window.isUnlimited, let total = window.totalCount {
                LabeledContent("总量", value: QuotaFormatting.count(total, unit: window.unit))
            }

            if let expiresAt = window.expiresAt {
                LabeledContent(window.id == "stepfun.credits" ? "最早积分到期" : "到期时间",
                               value: QuotaFormatting.resetDate(expiresAt))
            }
            if window.resetsAt != nil {
                LabeledContent("下次重置", value: QuotaFormatting.resetDate(window.resetsAt))
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
        guard let total = window.totalCount else { return QuotaFormatting.count(remaining, unit: window.unit) }
        let values = "\(QuotaFormatting.count(remaining)) / \(QuotaFormatting.count(total))"
        guard let unit = window.unit, !unit.isEmpty else { return values }
        return "\(values) \(unit)"
    }
}

struct WalletBalanceView: View {
    let balance: WalletBalance

    var body: some View {
        LabeledContent(balance.isMonetary ? "总可用余额" : "剩余 points",
                       value: QuotaFormatting.balance(balance.total, wallet: balance))
        if balance.isMonetary {
            LabeledContent("赠送余额", value: QuotaFormatting.balance(balance.granted, wallet: balance))
            LabeledContent("充值余额", value: QuotaFormatting.balance(balance.toppedUp, wallet: balance))
        }
    }
}

private struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newAccountID = UUID()
    @State private var name = ""
    @State private var key = ""
    @State private var serverAddress = ""
    @State private var provider = Provider.miniMaxChina
    @State private var saving = false
    @State private var showingLogin = false
    @State private var loginMessage: String?
    let isDemoMode: Bool
    let save: (String, String, Provider, UUID) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("服务") {
                    Picker("提供商", selection: $provider) {
                        ForEach(Provider.allCases) { provider in
                            Label {
                                Text(provider.displayName)
                            } icon: {
                                ProviderIcon(provider: provider, size: 20)
                            }
                            .tag(provider)
                        }
                    }
                }

                Section {
                    TextField("例如：工作账号", text: $name)
                        .textContentType(.nickname)
                } header: {
                    Text("账号名称")
                } footer: {
                    Text("名称只用于区分你自己的多个服务账号。")
                }

                if provider == .newAPI && !isDemoMode {
                    Section {
                        TextField("https://gateway.example.com/v1", text: $serverAddress)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: {
                        Text("服务器地址")
                    } footer: {
                        Text("每个账号可使用不同网关，末尾 /v1 会自动移除。公网需 HTTPS；本机与明确的私网地址可使用 HTTP。")
                    }
                }
                Section {
                    if isDemoMode {
                        Label("使用示例数据，无需登录或 API Key。", systemImage: "play.circle")
                    } else if usesAPIKey {
                        SecureField(credentialLabel, text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    } else {
                        Button(key.isEmpty ? "登录 \(provider.displayName)" : "重新登录", systemImage: "person.crop.circle.badge.checkmark") {
                            showingLogin = true
                        }
                        if !key.isEmpty {
                            Label("授权已完成", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    if let loginMessage {
                        Label(loginMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(isDemoMode ? "演示账号" : "登录凭证")
                } footer: {
                    Text(isDemoMode ? "新账号仅在演示模式中使用。" : "凭证保存在系统安全存储中，不会写入额度数据或日志。")
                }
            }
            .navigationTitle("添加账号")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                let credential = isDemoMode ? "demo" : usesAPIKey
                                    ? try ProviderAuthenticationController().credential(provider: provider, apiKey: key, serverAddress: serverAddress)
                                    : key
                                guard await save(isDemoMode ? "演示 · \(name)" : name, credential, provider, newAccountID) else {
                                    loginMessage = "账号未保存，请重试。"
                                    saving = false
                                    return
                                }
                            } catch {
                                loginMessage = provider == .newAPI ? "请输入有效的 服务器地址与 Key；地址不能包含用户信息、查询或片段。" : "无法保存登录凭证"
                                saving = false
                                return
                            }
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (!isDemoMode && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
                if saving {
                    ToolbarItem(placement: .status) { ProgressView() }
                }
            }
            .onChange(of: provider) { _, _ in key = ""; serverAddress = ""; loginMessage = nil }
            .sheet(isPresented: $showingLogin) {
                ProviderSignInView(provider: provider, accountID: newAccountID) { credential in
                    key = credential
                    showingLogin = false
                }
            }
        }
    }

    private var usesAPIKey: Bool {
        if case .apiKey = ProviderAuthenticationController().loginConfiguration(for: provider).method { return true }
        return false
    }

    private var credentialLabel: String {
        ProviderAuthenticationController().loginConfiguration(for: provider).credentialLabel ?? "API Key"
    }
}
