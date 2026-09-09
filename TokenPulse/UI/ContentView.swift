import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var monitor: QuotaMonitor
    let runtime: AppRuntime
    @State private var showingAddAccount = false
    @State private var linkedAccount: UUID?
    @State private var selectedTab = AppTab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if monitor.states.isEmpty {
                        ContentUnavailableView {
                            Label("添加订阅账号", systemImage: "waveform.path.ecg")
                        } description: {
                            Text("集中查看 Claude、Codex、OpenCode Go、Z.ai、MiniMax 和 SuperGrok 的套餐额度。")
                        } actions: {
                            AddAccountButton { showingAddAccount = true }
                        }
                    } else {
                        List {
                            if monitor.hasPendingCredentialCleanup {
                                Section {
                                    Button("重试凭证清理", systemImage: "arrow.clockwise.circle") {
                                        Task { await monitor.retryPendingCredentialCleanup() }
                                    }
                                } footer: {
                                    Text("上次移除未保存账号时，安全存储中的凭证未能清理。")
                                }
                            }
                            Section {
                                ForEach(monitor.states) { state in
                                    AccountQuotaView(
                                        state: state,
                                        isRefreshing: monitor.refreshingAccountIDs.contains(state.id),
                                        refresh: { await monitor.refresh(accountID: state.id) }
                                    )
                                    .listRowSeparator(.hidden)
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加账号", systemImage: "plus") { showingAddAccount = true }
                    }
                }
                .sheet(isPresented: $showingAddAccount) {
                    AddAccountView { name, key, provider in
                        let previousCount = monitor.states.count
                        await monitor.addAccount(name: name, credential: key, provider: provider)
                        return monitor.states.count > previousCount
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .alert("本地存储错误", isPresented: Binding(
                    get: { monitor.storageMessage != nil },
                    set: { if !$0 { monitor.dismissStorageMessage() } }
                )) {
                    Button("好") { monitor.dismissStorageMessage() }
                } message: {
                    Text(monitor.storageMessage ?? "")
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
    let state: AccountQuotaState
    let isRefreshing: Bool
    let refresh: () async -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = state.snapshot {
                    if let plan = snapshot.subscriptionPlan, state.account.provider == .codex {
                        LabeledContent("套餐", value: plan.displayName)
                    }
                    let detailWindows = snapshot.windows(for: state.account.provider, surface: .detail)
                    ForEach(detailWindows) { window in
                        if window.scope == nil {
                            QuotaWindowView(window: window)
                        } else {
                            LabeledContent(
                                window.scope ?? window.name,
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
            AccountSummaryView(state: state)
        }
    }
}

private struct AccountSummaryView: View {
    let state: AccountQuotaState

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
                ForEach(snapshot.windows(for: state.account.provider, surface: .summary)) { window in
                    CompactQuotaWindowView(window: window)
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
        guard state.account.provider == .codex,
              let plan = state.snapshot?.subscriptionPlan else { return state.account.provider.displayName }
        return "\(state.account.provider.displayName) · \(plan.displayName)"
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
                Text(window.name)
                    .font(.subheadline)
            }
            LabeledContent("下次重置", value: QuotaFormatting.resetDate(window.resetsAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var usedValue: String {
        QuotaFormatting.usage(window)
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

private struct QuotaWindowView: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(window.name)详情")
                .font(.subheadline)
                .bold()

            if let scope = window.scope {
                LabeledContent("范围", value: scope)
            }

            if let percentage = QuotaFormatting.effectiveUsedPercentage(window) {
                ProgressView(value: min(max(percentage, 0), 100), total: 100)
                    .accessibilityLabel("\(window.name)已用额度")
                    .accessibilityValue(QuotaFormatting.percentage(percentage))
            }

            if let remaining = window.remainingCount {
                LabeledContent("剩余", value: remainingValue(remaining))
            } else if let total = window.totalCount {
                LabeledContent("总量", value: QuotaFormatting.count(total))
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                if window.needsUpdate(at: context.date) {
                    Label("已到预计重置时间，等待刷新确认", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func remainingValue(_ remaining: Double) -> String {
        guard let total = window.totalCount else { return QuotaFormatting.count(remaining) }
        return "\(QuotaFormatting.count(remaining)) / \(QuotaFormatting.count(total))"
    }
}

private struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var key = ""
    @State private var provider = Provider.miniMaxChina
    @State private var saving = false
    @State private var showingLogin = false
    @State private var loginMessage: String?
    let save: (String, String, Provider) async -> Bool

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
                    Text("名称只用于区分你自己的多个订阅账号。")
                }

                Section {
                    if usesAPIKey {
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
                    Text("登录凭证")
                } footer: {
                    Text("凭证保存在系统安全存储中，不会写入额度数据或日志。")
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
                                let credential = usesAPIKey
                                    ? try ProviderAuthenticationController().credential(provider: provider, apiKey: key)
                                    : key
                                guard await save(name, credential, provider) else {
                                    loginMessage = "账号未保存，请重试。"
                                    saving = false
                                    return
                                }
                            } catch {
                                loginMessage = "无法保存登录凭证"
                                saving = false
                                return
                            }
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if saving {
                    ToolbarItem(placement: .status) { ProgressView() }
                }
            }
            .onChange(of: provider) { _, _ in key = ""; loginMessage = nil }
            .sheet(isPresented: $showingLogin) {
                ProviderSignInView(provider: provider) { credential in
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
