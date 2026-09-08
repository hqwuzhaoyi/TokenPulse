import SwiftUI

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var monitor: QuotaMonitor
    let runtime: AppRuntime
    var initialAccountID: UUID?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                CloudSyncSettingsSection(settings: runtime.cloudSync, runtime: runtime)
                Section("系统通知") {
                    Button("允许 TokenPulse 提醒") {
                        Task {
                            do {
                                let allowed = try await UserNotificationCenterAdapter().requestAuthorization()
                                monitor.setSynchronizationMessage(allowed ? "系统通知已开启" : "通知未开启，可前往系统设置修改。")
                                if allowed { await monitor.onChange?() }
                            } catch { monitor.setSynchronizationMessage("无法申请通知权限") }
                        }
                    }
                }
                if let message = monitor.synchronizationMessage {
                    Label(message, systemImage: "icloud").font(.caption)
                }
                Section("Watch 关注顺序") {
                    ForEach(monitor.followedAccounts) { configuration in
                        HStack(spacing: 10) {
                            ProviderIcon(provider: configuration.account.provider)
                            Text(configuration.account.name)
                        }
                    }
                    .onMove { from, to in Task { await monitor.reorderFollowed(from: from, to: to) } }
                }
                Section("全部账号") {
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
            .navigationTitle("账号设置")
            .navigationDestination(for: UUID.self) { id in AccountPreferencesView(monitor: monitor, accountID: id) }
            .onAppear { if let initialAccountID, path.isEmpty { path = [initialAccountID] } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct CloudSyncSettingsSection: View {
    @ObservedObject var settings: CloudSyncSettings
    let runtime: AppRuntime

    var body: some View {
        Section {
            Toggle("iCloud 同步", isOn: Binding(
                get: { settings.isEnabled },
                set: { enabled in Task { await runtime.setCloudSyncEnabled(enabled) } }
            ))
            Button {
                Task { await runtime.synchronizeNow() }
            } label: {
                HStack {
                    Label(settings.isSyncing ? "正在同步…" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                    if settings.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(!settings.isEnabled || settings.isSyncing)
            LabeledContent("上次同步请求") { timestamp(settings.lastRequestedAt) }
            LabeledContent("上次收到云端更新") { timestamp(settings.lastReceivedAt) }
            if let error = settings.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if !settings.isEnabled {
                Text("同步已关闭").font(.caption).foregroundStyle(.secondary)
            } else if settings.lastRequestedAt != nil {
                Text("同步请求已提交，跨设备传送由 iCloud 安排。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("同步")
        } footer: {
            Text("同步账号、额度、提醒设置及凭证。关闭后保留本机与已同步的数据；请求时间不代表 Watch 已收到。")
        }
    }

    @ViewBuilder
    private func timestamp(_ date: Date?) -> some View {
        if let date { Text(date, format: .dateTime.month().day().hour().minute().second()) }
        else { Text("暂无记录").foregroundStyle(.secondary) }
    }
}

private struct AccountPreferencesView: View {
    @ObservedObject var monitor: QuotaMonitor
    let accountID: UUID
    @State private var thresholds = ""
    @State private var error: String?
    @State private var credential = ""
    @State private var showingLogin = false

    var body: some View {
        Form {
            if let configuration = monitor.configuration(for: accountID) {
                if let state = monitor.states.first(where: { $0.id == accountID }) {
                    Section("额度") {
                        ForEach(state.snapshot?.windows ?? []) { window in
                            VStack(alignment: .leading) {
                                Text(window.name).font(.headline)
                                Text(window.isUnlimited ? "无限" : QuotaFormatting.percentage(window.usedPercentage))
                                Text("重置：\(QuotaFormatting.resetDate(window.resetsAt))")
                                if window.needsUpdate(at: Date()) { Text("待更新").foregroundStyle(.orange) }
                            }
                        }
                        if let snapshot = state.snapshot {
                            if configuration.account.provider == .codex {
                                LabeledContent("可手动重置", value: QuotaFormatting.remainingResets(snapshot.remainingResetCount))
                            }
                            Text("采集于 \(snapshot.collectedAt.formatted())").font(.caption)
                        } else { Text("尚无成功采集数据") }
                        if let failure = state.lastFailure { Text(failure.displayName).foregroundStyle(.orange) }
                        Button("刷新") { Task { await monitor.refresh(accountID: accountID) } }
                    }
                }
                Section("显示") {
                    Toggle("在 Watch 上关注", isOn: Binding(
                        get: { configuration.followOrder != nil },
                        set: { value in Task { await monitor.setFollowed(value, accountID: accountID) } }
                    ))
                }
                Section("提醒") {
                    Toggle("额度告警", isOn: Binding(get: { configuration.reminders.quotaAlertsEnabled }, set: { value in
                        var settings = configuration.reminders; settings.quotaAlertsEnabled = value
                        Task { await monitor.updateReminders(settings, accountID: accountID) }
                    }))
                    Toggle("重置提醒", isOn: Binding(get: { configuration.reminders.resetRemindersEnabled }, set: { value in
                        var settings = configuration.reminders; settings.resetRemindersEnabled = value
                        Task { await monitor.updateReminders(settings, accountID: accountID) }
                    }))
                    TextField("阈值，例如 80,95,100", text: $thresholds).keyboardType(.numbersAndPunctuation)
                    Button("保存阈值") {
                        let pieces = thresholds.split(separator: ",", omittingEmptySubsequences: false)
                        let values = pieces.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                        guard values.count == pieces.count, !values.isEmpty,
                              values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 100 }) else {
                            error = "请输入 0 到 100 之间的比例，使用英文逗号分隔。"; return
                        }
                        error = nil
                        var settings = configuration.reminders; settings.thresholds = Array(Set(values)).sorted()
                        Task { await monitor.updateReminders(settings, accountID: accountID) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Text("后台刷新由系统安排，提醒可能延迟；两台设备离线时可能分别提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("更新凭证") {
                    if configuration.account.provider == .miniMaxChina || configuration.account.provider == .zai {
                        SecureField("Coding Plan Key", text: $credential)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("保存并刷新") {
                            Task {
                                do {
                                    let encoded = configuration.account.provider == .zai
                                        ? try ProviderAuthenticationController().credential(provider: .zai, apiKey: credential)
                                        : credential
                                    await monitor.replaceCredential(encoded, accountID: accountID)
                                    credential = ""
                                } catch { self.error = "无法保存凭证" }
                            }
                        }.disabled(credential.isEmpty)
                    } else {
                        Button("重新登录 \(configuration.account.provider.displayName)") { showingLogin = true }
                    }
                }
            } else { Text("账号配置尚未同步") }
        }
        .navigationTitle(monitor.configuration(for: accountID)?.account.name ?? "账号")
        .sheet(isPresented: $showingLogin) {
            if let provider = monitor.configuration(for: accountID)?.account.provider {
                ProviderSignInView(provider: provider) { value in
                    showingLogin = false
                    Task { await monitor.replaceCredential(value, accountID: accountID) }
                }
            }
        }
        .onAppear {
            thresholds = monitor.configuration(for: accountID)?.reminders.thresholds.map { String($0) }.joined(separator: ",") ?? "80,95,100"
        }
    }
}
