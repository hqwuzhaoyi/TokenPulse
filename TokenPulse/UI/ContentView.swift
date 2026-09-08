import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var monitor: QuotaMonitor
    let runtime: AppRuntime
    @State private var showingAddAccount = false
    @State private var showingSettings = false
    @State private var linkedAccount: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if monitor.states.isEmpty {
                    ContentUnavailableView(
                        "添加订阅账号",
                        systemImage: "waveform.path.ecg",
                        description: Text("查看 Claude、Codex、Z.ai、MiniMax 和 SuperGrok 的套餐额度。")
                    )
                } else {
                    List(monitor.states) { state in
                        AccountQuotaView(
                            state: state,
                            isRefreshing: monitor.refreshingAccountIDs.contains(state.id),
                            refresh: { await monitor.refresh(accountID: state.id) }
                        )
                    }
                    .refreshable { await monitor.refreshAll() }
                }
            }
            .navigationTitle("TokenPulse")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("账号设置", systemImage: "gearshape") { linkedAccount = nil; showingSettings = true }
                }
                if monitor.hasPendingCredentialCleanup {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("重试凭证清理", systemImage: "arrow.clockwise.circle") {
                            Task { await monitor.retryPendingCredentialCleanup() }
                        }
                    }
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
            }
            .sheet(isPresented: $showingSettings) {
                AccountSettingsView(monitor: monitor, runtime: runtime, initialAccountID: linkedAccount)
            }
            .onOpenURL { url in
                if url.scheme == "tokenpulse", url.host == "account", let id = UUID(uuidString: url.lastPathComponent) {
                    linkedAccount = id
                    showingSettings = true
                }
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await monitor.applicationDidBecomeActive() }
        }
    }
}

private struct AccountQuotaView: View {
    let state: AccountQuotaState
    let isRefreshing: Bool
    let refresh: () async -> Void

    var body: some View {
        Section {
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(window.name).font(.headline)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            if window.needsUpdate(at: context.date) {
                                Text("待更新").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if let scope = window.scope { Text(scope).font(.caption).foregroundStyle(.secondary) }
                        if let limit = QuotaFormatting.limitDescription(window) {
                            LabeledContent("额度", value: limit)
                        } else {
                            LabeledContent("已用", value: QuotaFormatting.percentage(window.usedPercentage))
                        }
                        LabeledContent("重置时间", value: QuotaFormatting.resetDate(window.resetsAt))
                    }
                    .padding(.vertical, 4)
                }
                if state.account.provider == .codex {
                    LabeledContent("可手动重置", value: QuotaFormatting.remainingResets(snapshot.remainingResetCount))
                }
                Text("采集于 \(snapshot.collectedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("尚无成功采集数据").foregroundStyle(.secondary)
            }

            if let failure = state.lastFailure {
                Label(
                    QuotaFormatting.refreshFailure(failure, hasSnapshot: state.snapshot != nil),
                    systemImage: "exclamationmark.triangle"
                )
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            HStack {
                ProviderIcon(provider: state.account.provider, size: 24)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading) {
                    Text(state.account.name)
                    Text(state.account.provider.displayName).font(.caption)
                }
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isRefreshing)
                .accessibilityLabel("刷新 \(state.account.name)")
            }
        }
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
                TextField("账号名称", text: $name)
                if provider == .miniMaxChina || provider == .zai {
                    SecureField("Coding Plan Key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    Button(key.isEmpty ? "登录 \(provider.displayName)" : "重新登录") { showingLogin = true }
                    if !key.isEmpty { Label("已取得登录凭证", systemImage: "checkmark.circle") }
                }
                if let loginMessage { Text(loginMessage).foregroundStyle(.red) }
                Text("凭证保存在安全存储中，不会写入额度数据或日志。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("添加账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                let credential = provider == .zai
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
}
