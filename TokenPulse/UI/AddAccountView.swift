import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var newAccountID = UUID()
    @State private var name = ""
    @State private var key = ""
    @State private var serverAddress = ""
    @State private var region: ProviderRegion?
    @State private var organizationID = ""
    @State private var tokenPlanSite: AlibabaTokenPlanSite?
    @State private var provider = Provider.miniMaxChina
    @State private var saving = false
    @State private var showingLogin = false
    @State private var loginMessage: String?
    let isDemoMode: Bool
    let existingProviders: Set<Provider>
    let save: (String, String, Provider, UUID) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("服务") {
                    NavigationLink {
                        ProviderSelectionView(selection: $provider, existingProviders: existingProviders)
                    } label: {
                        providerPickerLabel
                    }
                    .disabled(saving)
                }

                Section {
                    TextField("例如：工作账号", text: $name)
                        .textContentType(.nickname)
                } header: {
                    Text("账号名称")
                } footer: {
                    Text("名称只用于区分你自己的多个服务账号。")
                }

                if provider.requiresRegion && !isDemoMode {
                    Section("服务地区") {
                        ProviderRegionPicker(region: $region, usesCloudRegionNames: provider == .alibabaTokenPlan)
                        if provider == .alibabaTokenPlan {
                            AlibabaTokenPlanSitePicker(site: $tokenPlanSite)
                        }
                        Text(L10n.text(provider == .alibabaTokenPlan
                                 ? "选择北京或新加坡及账号所属站点。输入 AK:SK，不是 sk-sp 推理 Key；仅查询个人 Token Plan。更换地区或站点需要重新输入凭证。"
                                 : provider == .moonshot
                             ? "Moonshot 开放平台 API 钱包与 Kimi Code 套餐不同。Key 只发送至所选地区；更换地区需要重新输入对应 Key。"
                             : "Key 只发送至所选百炼地区。部分账号的接口要求控制台登录会话；此版本仅支持 Key 路线，真实 Key 兼容性仍待验证。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if provider.requiresGatewayAddress && !isDemoMode {
                    Section {
                        TextField("https://gateway.example.com/v1", text: $serverAddress)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: {
                        Text("服务器地址")
                    } footer: {
                        Text("每个账号可使用不同网关，末尾 /v1 会自动移除。公网需 HTTPS；本机与明确的私网地址可使用 HTTP。")
                    }
                }
                if provider == .gitKraken && !isDemoMode {
                    Section("查询组织") {
                        TextField("组织 ID（可选）", text: $organizationID)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("留空查询会话默认组织；组织额度会标明配置的 ID。会话 Token 会过期，失效后请在账号设置重新配置。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if isDemoMode {
                        Label("使用示例数据，无需登录或 API Key。", systemImage: "play.circle")
                    } else if usesAPIKey {
                        if provider == .volcengine {
                            Text("输入 AccessKeyID:SecretAccessKey，使用英文冒号。两个套餐分别查询；AK/SK 仅保存在系统安全存储中。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if provider == .xaiAPI {
                            Text("输入 TeamID:ManagementKey，使用英文冒号。需要管理 Key 和账单读取权限，推理 Key 无效。余额是已入账值，账期内可能高于控制台实时余额。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if provider == .ibmBob {
                            Text("通用 API Key 输入 apikey:Key；登录 JWT 输入 token:JWT。推理专用 Key 不适用。各实例和团队的 Bobcoins 预算分别展示，不换算成货币。登录 token 到期后需更新。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if provider == .openAIAPI {
                            Text(L10n.text(OpenAIAPIProviderClient.connectionNotice))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        SecureField(credentialLabel, text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    } else {
                        Button(key.isEmpty ? L10n.format("登录 %@", provider.displayName) : L10n.text("重新登录"), systemImage: "person.crop.circle.badge.checkmark") {
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
                    Text(L10n.text(isDemoMode ? "演示账号" : "登录凭证"))
                } footer: {
                    Text(L10n.text(isDemoMode ? "新账号仅在演示模式中使用。" : "凭证保存在系统安全存储中，不会写入额度数据或日志。"))
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
                                    ? try ProviderAuthenticationController().credential(provider: provider, apiKey: key, serverAddress: serverAddress, region: region, organizationID: organizationID, tokenPlanSite: tokenPlanSite)
                                    : key
                                guard await save(isDemoMode ? "演示 · \(name)" : name, credential, provider, newAccountID) else {
                                    loginMessage = L10n.text("账号未保存，请重试。")
                                    saving = false
                                    return
                                }
                            } catch {
                                loginMessage = L10n.text(provider.requiresGatewayAddress ? "请输入有效的服务器地址与 Key；地址不能包含用户信息、查询或片段。" : "无法保存登录凭证")
                                saving = false
                                return
                            }
                            saving = false
                            dismiss()
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (!isDemoMode && (key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                 || provider.requiresRegion && region == nil
                                                 || provider == .alibabaTokenPlan && tokenPlanSite == nil)))
                }
                if saving {
                    ToolbarItem(placement: .status) { ProgressView() }
                }
            }
            .onChange(of: provider) { _, _ in key = ""; serverAddress = ""; region = nil; organizationID = ""; tokenPlanSite = nil; loginMessage = nil }
            .onChange(of: region) { _, _ in key = ""; loginMessage = nil }
            .onChange(of: tokenPlanSite) { _, _ in key = ""; loginMessage = nil }
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

    private var providerPickerLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        } else {
            AnyLayout(HStackLayout(spacing: 12))
        }
    }

    private var providerPickerLabel: some View {
        providerPickerLayout {
            HStack(alignment: .top, spacing: 12) {
                ProviderIcon(provider: provider, size: 24)
                    .foregroundStyle(Color.primary)
                Text(provider.displayName)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text("更换")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 6)
    }


    private var credentialLabel: String {
        L10n.text(ProviderAuthenticationController().loginConfiguration(for: provider).credentialLabel ?? "API Key")
    }
}

struct ProviderRegionPicker: View {
    @Binding var region: ProviderRegion?
    var usesCloudRegionNames = false
    var body: some View {
        Picker("地区", selection: $region) {
            Text("请选择服务地区").tag(Optional<ProviderRegion>.none)
            ForEach(ProviderRegion.allCases) { region in
                Text(usesCloudRegionNames ? region.cloudDisplayName : region.displayName).tag(Optional(region))
            }
        }
    }
}

struct AlibabaTokenPlanSitePicker: View {
    @Binding var site: AlibabaTokenPlanSite?
    var body: some View {
        Picker("账号站点", selection: $site) {
            Text("请选择账号站点").tag(Optional<AlibabaTokenPlanSite>.none)
            ForEach(AlibabaTokenPlanSite.allCases) { site in
                Text(site.displayName).tag(Optional(site))
            }
        }
    }
}


/// A searchable destination keeps the full catalog accessible without a long menu.
private struct ProviderSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Provider
    let existingProviders: Set<Provider>
    @State private var query = ""

    private var catalog: ProviderSelectionCatalog {
        ProviderSelectionCatalog(existingProviders: existingProviders)
    }

    private var results: [Provider] { catalog.results(for: query) }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
                Section(L10n.format("搜索结果 · %ld", results.count)) {
                    ForEach(results) { provider in row(provider) }
                }
            } else {
                if !existingProviders.isEmpty {
                    Section("已添加的服务") {
                        ForEach(catalog.addedProviders) { provider in
                            row(provider)
                        }
                    }
                    .modifier(ProviderSectionIndexLabel(title: "★"))
                }
                ForEach(catalog.sections) { group in
                    Section(group.title) {
                        ForEach(group.providers) { provider in row(provider) }
                    }
                    .modifier(ProviderSectionIndexLabel(title: group.indexLabel))
                }
            }
        }
        .listStyle(.plain)
        .modifier(ProviderSectionIndexVisibility(isSearching: isSearching))
        .navigationTitle("选择提供商")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索名称，如 Claude、智谱")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if isSearching && results.isEmpty {
                ContentUnavailableView {
                    Label("未找到服务", systemImage: "magnifyingglass")
                } description: {
                    Text(L10n.format("未找到与“%@”匹配的 Provider。", query))
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func row(_ provider: Provider) -> some View {
        Button {
            selection = provider
            dismiss()
        } label: {
            HStack(spacing: 14) {
                ProviderIcon(provider: provider, size: 24)
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                Text(provider.displayName)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selection == provider {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selection == provider ? .isSelected : [])
    }

}

/// One presentation catalog drives search, visible groups, and native index destinations.
struct ProviderSelectionCatalog {
    struct Section: Identifiable {
        let id: String
        let title: String
        let indexLabel: String
        let providers: [Provider]
    }

    let existingProviders: Set<Provider>
    var language: String? = nil

    var providers: [Provider] {
        Provider.allCases.sorted {
            let comparison = $0.displayName(language: language)
                .localizedStandardCompare($1.displayName(language: language))
            return comparison == .orderedSame ? $0.rawValue < $1.rawValue : comparison == .orderedAscending
        }
    }

    var addedProviders: [Provider] { providers.filter { existingProviders.contains($0) } }

    var sections: [Section] {
        let remaining = providers.filter { !existingProviders.contains($0) }
        let grouped = Dictionary(grouping: remaining) { provider in
            let first = String(provider.displayName(language: language).prefix(1)).uppercased()
            return first.range(of: "^[A-Z]$", options: .regularExpression) != nil ? first : "#"
        }
        return grouped.keys.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }.map { index in
            Section(id: index, title: index == "#" ? L10n.text("其他", language: language) : index,
                    indexLabel: index, providers: grouped[index] ?? [])
        }
    }

    func results(for query: String) -> [Provider] {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        return providers.filter { provider in
            // Keep both languages searchable when a translated region descriptor changes the visible name.
            let text = "\(provider.displayName(language: language)) \(provider.displayName(language: "zh-Hans")) \(provider.displayName(language: "en")) \(provider.rawValue) \(Self.aliases(for: provider))"
                .replacingOccurrences(of: ".", with: "")
            return terms.allSatisfy {
                text.localizedStandardContains(String($0).replacingOccurrences(of: ".", with: ""))
            }
        }
    }

    private static func aliases(for provider: Provider) -> String {
        switch provider {
        case .claude: "Anthropic Claude Code"
        case .codex: "OpenAI ChatGPT"
        case .zhipu, .zai: "智谱 Zhipu Zai GLM"
        case .alibabaCodingPlan, .alibabaTokenPlan: "Alibaba 百炼 阿里 通义 Qwen"
        case .volcengine: "Volcengine 火山 豆包 方舟"
        case .kimiCode, .moonshot: "月之暗面 Kimi Moonshot"
        case .stepFun: "阶跃星辰 StepFun"
        case .deepSeek: "深度求索 DeepSeek"
        case .xiaomiCodingPlan: "小米 Xiaomi Mimo"
        case .qwenCloud: "通义 千问 Qwen"
        case .miniMaxChina: "MiniMax 海螺 国内 中国 China"
        case .miniMaxInternational: "MiniMax 海螺 国际 International"
        case .qoderChina: "Qoder 国内 中国 China"
        case .qoderInternational: "Qoder 国际 International"
        default: ""
        }
    }
}


private struct ProviderSectionIndexLabel: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.sectionIndexLabel(title)
        } else {
            content
        }
    }
}

private struct ProviderSectionIndexVisibility: ViewModifier {
    let isSearching: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.listSectionIndexVisibility(isSearching ? .hidden : .visible)
        } else {
            content
        }
    }
}
