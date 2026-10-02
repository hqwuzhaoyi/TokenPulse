import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var monitor: QuotaMonitor
    @ObservedObject var runtime: AppRuntime
    var initialAccountID: UUID?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button(runtime.isDemoMode ? "退出演示 / Exit Demo" : "体验演示 / Try Demo") {
                        Task { await runtime.setDemoMode(!runtime.isDemoMode) }
                    }
                    .disabled(runtime.isSwitchingMode)
                } footer: {
                    Text(runtime.isDemoMode
                         ? "当前显示示例数据，可刷新、添加或删除演示账号。退出后恢复真实账号。"
                         : "无需第三方账号即可体验额度、账号管理、提醒和小组件。")
                }
                if runtime.isDemoMode {
                    Section("同步") {
                        Text("示例数据仅保存在本机。iPhone 和 Watch 可分别进入演示；退出演示后可使用 iCloud 同步真实账号。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    CloudSyncSettingsSection(settings: runtime.cloudSync, runtime: runtime)
                }
                NotificationSettingsSection(notifications: runtime.notifications, monitor: monitor,
                                            isDemoMode: runtime.isDemoMode)
                if let message = monitor.synchronizationMessage {
                    Label(message, systemImage: "info.circle").font(.caption)
                }
                Section("全部服务账号") {
                    ForEach(monitor.configurations) { configuration in
                        NavigationLink(value: configuration.id) {
                            HStack(spacing: 10) {
                                ProviderIcon(provider: configuration.account.provider, size: 24)
                                VStack(alignment: .leading) {
                                    Text(configuration.account.name)
                                    Text(configuration.account.provider.displayName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationDestination(for: UUID.self) { id in
                AccountPreferencesView(monitor: monitor, accountID: id, isDemoMode: runtime.isDemoMode)
            }
            .onAppear { if let initialAccountID, path.isEmpty { path = [initialAccountID] } }
            .onChange(of: initialAccountID) { _, accountID in
                if let accountID { path = [accountID] }
            }
        }
    }
}

private struct NotificationSettingsSection: View {
    @ObservedObject var notifications: NotificationRuntime
    @ObservedObject var monitor: QuotaMonitor
    let isDemoMode: Bool
    @State private var isUpdating = false

    var body: some View {
        Section {
            Toggle("通知", isOn: Binding(
                get: { notifications.isEnabled },
                set: { enabled in update(enabled) }
            ))
            .disabled(isUpdating)
            if isDemoMode {
                Button("发送演示通知") {
                    isUpdating = true
                    Task {
                        let feedback = await notifications.sendDemoNotification()
                        monitor.setSynchronizationMessage(feedback == .enabled
                            ? "演示通知已提交，可在通知中心查看。"
                            : feedback.message)
                        isUpdating = false
                    }
                }
                .disabled(isUpdating)
            }
        } header: {
            Text("通知")
        } footer: {
            Text(isDemoMode
                 ? "演示提醒使用系统通知权限，仅用于示例账号。退出演示会取消未触发的演示提醒。"
                 : "关闭会暂停所有额度与重置提醒，但保留每个账号的提醒类型和阈值。")
        }
    }

    private func update(_ enabled: Bool) {
        isUpdating = true
        Task {
            let feedback = await notifications.setEnabled(
                enabled,
                configurations: monitor.configurations,
                states: monitor.states
            )
            monitor.setSynchronizationMessage(feedback.message)
            isUpdating = false
        }
    }
}

private struct CloudSyncSettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var settings: CloudSyncSettings
    let runtime: AppRuntime
    @State private var syncRotation = 0.0

    var body: some View {
        Section {
            Toggle("iCloud 同步", isOn: Binding(
                get: { settings.isEnabled },
                set: { enabled in Task { await runtime.setCloudSyncEnabled(enabled) } }
            ))
            Button {
                withAnimation(reduceMotion ? nil : .linear(duration: 0.6)) {
                    syncRotation += 360
                }
                Task { await runtime.synchronizeNow() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(syncRotation))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text("立即同步")
                    Spacer()
                    latestSyncTime
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.isEnabled)
            .allowsHitTesting(!settings.isSyncing)
            .accessibilityValue(settings.isSyncing ? "正在同步" : "")
            if let error = settings.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if !settings.isEnabled {
                Text("同步已关闭").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("同步")
        }
    }

    @ViewBuilder
    private var latestSyncTime: some View {
        if let date = [settings.lastRequestedAt, settings.lastReceivedAt].compactMap({ $0 }).max() {
            Text(date, format: .dateTime.month().day().hour().minute())
        } else {
            Text("暂无")
        }
    }
}

private struct AccountPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var monitor: QuotaMonitor
    let accountID: UUID
    let isDemoMode: Bool
    @State private var thresholds = ""
    @State private var walletThreshold = ""
    @State private var error: String?
    @State private var credential = ""
    @State private var serverAddress = ""
    @State private var region: ProviderRegion?
    @State private var showingLogin = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            if let configuration = monitor.configuration(for: accountID) {
                if let state = monitor.states.first(where: { $0.id == accountID }) {
                    Section("额度") {
                        if let snapshot = state.snapshot {
                            if let plan = snapshot.subscriptionPlan, configuration.account.provider == .codex {
                                LabeledContent("套餐", value: plan.displayName)
                            }
                            if configuration.account.provider == .stepFun, snapshot.windows.isEmpty {
                                Text("当前账号没有可用的 Step Plan")
                            }
                            if let plan = snapshot.providerPlanName {
                                LabeledContent("套餐", value: plan)
                            }
                            ForEach(snapshot.windows(for: configuration.account.provider, surface: .detail)) { window in
                                if window.scope == nil || [.qoderInternational, .zai, .zhipu, .miniMaxChina, .miniMaxInternational, .cursor].contains(configuration.account.provider) {
                                    QuotaWindowView(window: window)
                                } else {
                                    LabeledContent(
                                        window.displayName,
                                        value: QuotaFormatting.usage(window)
                                    )
                                }
                            }
                            if configuration.account.provider == .codex {
                                LabeledContent("可手动重置", value: QuotaFormatting.remainingResets(snapshot.remainingResetCount))
                            }
                            if snapshot.walletAvailable == false {
                                Label(QuotaFormatting.walletUnavailableDetail, systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            if snapshot.quotaExceeded == true {
                                Label(QuotaFormatting.quotaExceededBadge, systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text("采集于 \(snapshot.collectedAt.formatted())").font(.caption)
                        } else { Text("尚无成功采集数据") }
                        if let failure = state.lastFailure { Text(failure.displayName).foregroundStyle(.orange) }
                        Button("刷新") { Task { await monitor.refresh(accountID: accountID) } }
                    }
                }
                let quotaRemindersAvailable = supportsQuotaReminders(configuration)
                let walletRemindersAvailable = supportsWalletReminders(configuration)
                if quotaRemindersAvailable || walletRemindersAvailable {
                    Section("提醒") {
                        if quotaRemindersAvailable {
                            Toggle("额度告警", isOn: Binding(get: { configuration.reminders.quotaAlertsEnabled }, set: { value in
                                var settings = configuration.reminders; settings.quotaAlertsEnabled = value
                                Task { await monitor.updateReminders(settings, accountID: accountID) }
                            }))
                            if configuration.account.provider != .qoderInternational &&
                                (configuration.account.provider != .stepFun || monitor.states.first(where: { $0.id == accountID })?.snapshot?.windows.contains(where: { $0.resetsAt != nil }) == true) &&
                                (configuration.account.provider.balancePresentation != .mixed || monitor.states.first(where: { $0.id == accountID })?.snapshot?.windows.contains(where: { $0.wallet == nil && $0.resetsAt != nil }) == true) {
                                Toggle("重置提醒", isOn: Binding(get: { configuration.reminders.resetRemindersEnabled }, set: { value in
                                    var settings = configuration.reminders; settings.resetRemindersEnabled = value
                                    Task { await monitor.updateReminders(settings, accountID: accountID) }
                                }))
                            }
                            TextField("阈值，例如 80,95,100", text: $thresholds).keyboardType(.numbersAndPunctuation)
                            Button("保存阈值") { saveQuotaThresholds(configuration) }
                        }
                        if walletRemindersAvailable {
                            Toggle("低余额提醒", isOn: Binding(get: { configuration.reminders.effectiveWalletAlertsEnabled }, set: { value in
                                var settings = configuration.reminders; settings.walletAlertsEnabled = value
                                Task { await monitor.updateReminders(settings, accountID: accountID) }
                            }))
                            walletReminderControls(configuration: configuration)
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                        Text("后台刷新由系统安排，提醒可能延迟；两台设备离线时可能分别提醒。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Apple Watch") {
                    Toggle("在 Watch 显示", isOn: Binding(
                        get: { configuration.isWatchFavorite != false },
                        set: { enabled in
                            Task { await monitor.updateWatchFavorite(enabled, accountID: accountID) }
                        }
                    ))
                }
                Section("更新凭证") {
                    if isDemoMode {
                        Text("演示账号无需真实凭证。")
                        Button("重新连接演示账号") {
                            Task { await monitor.replaceCredential("demo", accountID: accountID) }
                        }
                    } else if usesAPIKey(configuration.account.provider) {
                        if configuration.account.provider.requiresRegion {
                            ProviderRegionPicker(region: $region)
                            Text(configuration.account.provider == .moonshot
                                 ? "地区与凭证绑定；更换地区需要对应 Key，并清除旧余额和提醒记录。"
                                 : "地区与凭证绑定。Key 查询兼容性待验证；要求控制台会话时不会显示零额度。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if configuration.account.provider == .newAPI {
                            TextField("服务器地址", text: $serverAddress)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("更换地址或 Key 会清除该账号的旧余额与提醒记录。公网需 HTTPS；本机与明确的私网地址可使用 HTTP。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        SecureField(credentialLabel(configuration.account.provider), text: $credential)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("保存并刷新") {
                            Task {
                                do {
                                    let encoded = usesAPIKey(configuration.account.provider)
                                        ? try ProviderAuthenticationController().credential(
                                            provider: configuration.account.provider,
                                            apiKey: credential,
                                            serverAddress: serverAddress, region: region
                                        )
                                        : credential
                                    await monitor.replaceCredential(encoded, accountID: accountID)
                                    credential = ""
                                } catch { self.error = configuration.account.provider == .newAPI ? "请输入有效的 服务器地址与 Key；地址不能包含用户信息、查询或片段。" : "无法保存凭证" }
                            }
                        }.disabled(credential.isEmpty || configuration.account.provider.requiresRegion && region == nil)
                    } else {
                        Button("重新登录 \(configuration.account.provider.displayName)") { showingLogin = true }
                    }
                }
                Section {
                    Button("删除账号", role: .destructive) { showingDeleteConfirmation = true }
                }
            } else { Text("账号配置尚未同步") }
        }
        .navigationTitle(monitor.configuration(for: accountID)?.account.name ?? "账号")
        .onAppear {
            serverAddress = monitor.configuration(for: accountID)?.serverAddress ?? ""
            region = monitor.configuration(for: accountID)?.providerRegion
        }
        .onChange(of: region) { _, _ in credential = "" }
        .confirmationDialog("删除账号？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除账号", role: .destructive) {
                Task { if await monitor.deleteAccount(accountID: accountID) { dismiss() } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(isDemoMode
                 ? "将移除此演示账号及其示例数据。真实账号不受影响。"
                 : "将移除此账号的凭证、额度数据和提醒；开启 iCloud 同步后也会从其他设备移除。")
        }
        .sheet(isPresented: $showingLogin) {
            if let provider = monitor.configuration(for: accountID)?.account.provider {
                ProviderSignInView(provider: provider, accountID: accountID) { value in
                    showingLogin = false
                    Task { await monitor.replaceCredential(value, accountID: accountID) }
                }
            }
        }
        .onAppear {
            thresholds = monitor.configuration(for: accountID)?.reminders.thresholds.map { String($0) }.joined(separator: ",") ?? "80,95,100"
            loadWalletThreshold()
        }
    }

    private func supportsQuotaReminders(_ configuration: AccountConfiguration) -> Bool {
        guard configuration.account.provider.balancePresentation != .walletOnly else { return false }
        guard configuration.account.provider.balancePresentation == .mixed,
              let snapshot = monitor.states.first(where: { $0.id == accountID })?.snapshot else { return true }
        return snapshot.windows.contains { $0.wallet == nil && !$0.isUnlimited && ($0.usedPercentage != nil || $0.totalCount != nil) }
    }

    private func supportsWalletReminders(_ configuration: AccountConfiguration) -> Bool {
        guard let snapshot = monitor.states.first(where: { $0.id == accountID })?.snapshot else {
            return configuration.account.provider.hasMonetaryWallet
        }
        return snapshot.windows.contains { $0.wallet?.isMonetary == true }
    }

    @ViewBuilder
    private func walletReminderControls(configuration: AccountConfiguration) -> some View {
        let currencies = monitor.states.first(where: { $0.id == accountID })?.snapshot?.windows
            .compactMap(\.wallet).filter(\.isMonetary).map(\.currency).uniqued() ?? []
        if currencies.isEmpty {
            Text("成功刷新后可选择提醒币种。")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("币种", selection: Binding(
                get: { configuration.reminders.walletCurrency ?? currencies[0] },
                set: { currency in
                    var settings = configuration.reminders
                    settings.walletCurrency = currency
                    walletThreshold = String(describing: settings.walletThreshold(for: currency))
                    Task { await monitor.updateReminders(settings, accountID: accountID) }
                }
            )) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
            TextField("低余额阈值", text: $walletThreshold)
                .keyboardType(.decimalPad)
            Button("保存低余额阈值") {
                let currency = configuration.reminders.walletCurrency ?? currencies[0]
                let input = walletThreshold.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Decimal(string: input, locale: .autoupdatingCurrent), !value.isNaN, value >= 0 else {
                    error = "请输入大于或等于 0 的金额。"
                    return
                }
                error = nil
                var settings = configuration.reminders
                settings.walletCurrency = currency
                var values = settings.walletThresholds ?? [:]
                values[currency] = value
                settings.walletThresholds = values
                Task { await monitor.updateReminders(settings, accountID: accountID) }
            }
        }
    }

    private func saveQuotaThresholds(_ configuration: AccountConfiguration) {
        let pieces = thresholds.split(separator: ",", omittingEmptySubsequences: false)
        let values = pieces.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == pieces.count, !values.isEmpty,
              values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100 }) else {
            error = "请输入 0 到 100 之间的比例，使用英文逗号分隔。"
            return
        }
        error = nil
        var settings = configuration.reminders
        settings.thresholds = Array(Set(values)).sorted()
        Task { await monitor.updateReminders(settings, accountID: accountID) }
    }

    private func loadWalletThreshold() {
        guard let configuration = monitor.configuration(for: accountID),
              let snapshot = monitor.states.first(where: { $0.id == accountID })?.snapshot,
              let currency = configuration.reminders.walletCurrency
                ?? snapshot.windows.compactMap(\.wallet?.currency).first else { return }
        walletThreshold = String(describing: configuration.reminders.walletThreshold(for: currency))
    }

    private func usesAPIKey(_ provider: Provider) -> Bool {
        if case .apiKey = ProviderAuthenticationController().loginConfiguration(for: provider).method { return true }
        return false
    }

    private func credentialLabel(_ provider: Provider) -> String {
        ProviderAuthenticationController().loginConfiguration(for: provider).credentialLabel ?? "API Key"
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
