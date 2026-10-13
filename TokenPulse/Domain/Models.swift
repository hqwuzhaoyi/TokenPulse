import Foundation

enum ProviderBalancePresentation: Sendable {
    case none
    case walletOnly
    case mixed
}

enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case miniMaxChina
    case claude, codex, openCodeGo, zai, superGrok
    case qoderInternational, deepSeek, kimiCode, elevenLabs, poe, vercelAIGateway
    case zhipu, miniMaxInternational
    case stepFun
    case newAPI
    case sub2api
    case bifrost
    case liteLLM
    case llmProxy
    case copilot
    case clinePass
    case clawRouter
    case aixy
    case neuralwatt
    case codebuff
    case moonshot
    case factory
    case augmentCode, zed, grokBot, gemini
    case venice
    case hyper
    case deepInfra
    case kiloCode
    case atlasCloud
    case commandCode, amp, gitKraken, huggingFace
    case synthetic, v2ex, xKiro, zenMux
    case alibabaCodingPlan, alibabaTokenPlan, chutes, cursor
    case volcengine
    case xaiAPI
    case ibmBob
    case warp, v0, devPass
    case raycastAI, t3Chat, zoomMate, qwenCloud, typeSafe
    case devin, manus, windsurf
    case nousPortal, jetBrainsAI
    case replicate, mistral, sakana, kiro
    case xiaomiCodingPlan, qoderChina, ollamaCloud, longCat
    case notionAI
    case perplexity
    case abacus
    case openAIAPI
    case antigravity

    var id: String { rawValue }
    var requiresRegion: Bool { self == .moonshot || self == .alibabaCodingPlan || self == .alibabaTokenPlan }
    var hasMonetaryWallet: Bool { [.openAIAPI, .perplexity, .xiaomiCodingPlan, .sub2api, .sakana, .mistral, .replicate, .devin, .typeSafe, .xaiAPI, .xKiro, .zenMux, .commandCode, .amp, .neuralwatt, .deepSeek, .vercelAIGateway, .newAPI, .moonshot, .atlasCloud, .kiloCode, .deepInfra, .venice].contains(self) }
    var requiresDeviceLocalCredential: Bool { [.nousPortal, .jetBrainsAI].contains(self) }
    var hasWalletBalance: Bool { hasMonetaryWallet || [.poe, .codebuff, .hyper, .manus, .nousPortal].contains(self) }
    var balancePresentation: ProviderBalancePresentation {
        switch self {
        case .openAIAPI, .perplexity, .replicate, .deepSeek, .vercelAIGateway, .newAPI, .poe, .moonshot, .atlasCloud, .hyper, .venice, .xaiAPI, .typeSafe: .walletOnly
        case .nousPortal, .xiaomiCodingPlan, .sub2api, .sakana, .mistral, .manus, .devin, .xKiro, .zenMux, .commandCode, .amp, .codebuff, .neuralwatt, .kiloCode, .deepInfra: .mixed
        default: .none
        }
    }
    var displayName: String { displayName(language: nil) }

    func displayName(language: String?) -> String {
        switch self {
        case .miniMaxChina: L10n.text("MiniMax 国内版", language: language)
        case .miniMaxInternational: L10n.text("MiniMax 国际版", language: language)
        case .zhipu: L10n.text("智谱国内版", language: language)
        case .claude: "Claude"
        case .codex: "Codex"
        case .openCodeGo: "OpenCode Go"
        case .zai: "Z.ai"
        case .superGrok: "SuperGrok"
        case .qoderInternational: L10n.text("Qoder 国际版", language: language)
        case .deepSeek: "DeepSeek"
        case .poe: "Poe"
        case .vercelAIGateway: "Vercel AI Gateway"
        case .kimiCode: L10n.text("Kimi Code 国内版", language: language)
        case .elevenLabs: "ElevenLabs"
        case .stepFun: "StepFun"
        case .newAPI: "New API"
        case .sub2api: "sub2api"
        case .bifrost: "Bifrost"
        case .liteLLM: "LiteLLM"
        case .llmProxy: "LLM API Key Proxy"
        case .copilot: "GitHub Copilot"
        case .clinePass: "ClinePass"
        case .clawRouter: "ClawRouter"
        case .aixy: "Aixy"
        case .neuralwatt: "Neuralwatt"
        case .codebuff: "Codebuff"
        case .moonshot: L10n.text("Moonshot API 钱包", language: language)
        case .factory: "Factory"
        case .augmentCode: "Augment Code"
        case .zed: "Zed"
        case .grokBot: "Grok Bot"
        case .gemini: "Gemini Code Assist"
        case .venice: "Venice"
        case .hyper: "Hyper"
        case .deepInfra: "DeepInfra"
        case .kiloCode: "Kilo Code"
        case .atlasCloud: "Atlas Cloud"
        case .commandCode: "Command Code"
        case .amp: "Amp"
        case .gitKraken: "GitKraken AI"
        case .huggingFace: "Hugging Face"
        case .synthetic: "Synthetic"
        case .v2ex: "V2EX"
        case .xKiro: "xKiro"
        case .zenMux: "ZenMux"
        case .alibabaCodingPlan: L10n.text("阿里百炼 Coding Plan", language: language)
        case .alibabaTokenPlan: L10n.text("阿里百炼 Token Plan", language: language)
        case .chutes: "Chutes"
        case .cursor: "Cursor"
        case .volcengine: L10n.text("火山方舟", language: language)
        case .xaiAPI: "xAI API"
        case .ibmBob: "IBM Bob"
        case .typeSafe: "TypeSafe"
        case .qwenCloud: "Qwen Cloud"
        case .raycastAI: "Raycast AI"
        case .t3Chat: "T3 Chat"
        case .zoomMate: "ZoomMate"
        case .warp: "Warp"
        case .v0: "v0"
        case .devPass: "DevPass"
        case .devin: "Devin"
        case .manus: "Manus"
        case .windsurf: "Windsurf"
        case .nousPortal: "Nous Portal"
        case .jetBrainsAI: "JetBrains AI"
        case .replicate: "Replicate"
        case .mistral: "Mistral"
        case .sakana: "Sakana AI"
        case .kiro: "Kiro"
        case .xiaomiCodingPlan: L10n.text("小米 Coding Plan", language: language)
        case .qoderChina: L10n.text("Qoder 国内版", language: language)
        case .ollamaCloud: "Ollama Cloud"
        case .longCat: "LongCat"
        case .notionAI: "Notion AI"
        case .perplexity: "Perplexity API"
        case .abacus: "Abacus AI"
        case .openAIAPI: L10n.text("OpenAI API（Legacy 余额）", language: language)
        case .antigravity: "Antigravity"
        }
    }
}
/// Region is an explicit credential choice, never inferred by trying another host.
enum ProviderRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case china, international
    var id: String { rawValue }
    var displayName: String { displayName(language: nil) }

    func displayName(language: String?) -> String {
        L10n.text(self == .china ? "国内（中国）" : "国际", language: language)
    }

    var cloudDisplayName: String {
        L10n.text(self == .china ? "北京（cn-beijing）" : "新加坡（ap-southeast-1）")
    }
}

struct SubscriptionAccount: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let provider: Provider

    init(id: UUID = UUID(), name: String, provider: Provider = .miniMaxChina) {
        self.id = id
        self.name = name
        self.provider = provider
    }
}

enum SubscriptionPlan: String, Codable, Equatable, Sendable {
    case plus
    case pro

    var displayName: String {
        switch self {
        case .plus: "Plus"
        case .pro: "Pro"
        }
    }
}

enum QuotaPeriod: String, Codable, Equatable, Sendable {
    case fiveHour
    case weekly
    case monthly
    case other

    init(seconds: Int?) {
        guard let seconds else { self = .other; return }
        self = switch seconds {
        case 5 * 3_600: .fiveHour
        case 7 * 86_400: .weekly
        case 28 * 86_400...31 * 86_400: .monthly
        default: .other
        }
    }
}

enum QuotaSurface: Sendable {
    case summary
    case detail
    case widget
    case notification
}

struct QuotaPolicy {
    static func windows(_ windows: [QuotaWindow],
                        provider: Provider,
                        plan: SubscriptionPlan?,
                        surface: QuotaSurface) -> [QuotaWindow] {
        guard provider == .codex else { return windows }

        let accountWide = windows.filter { $0.scope == nil }
        let primary = plan == .pro
            ? accountWide.filter { $0.period != .fiveHour }
            : accountWide
        guard surface == .detail else { return primary }

        var seenScopes: Set<String> = []
        let auxiliary = windows.filter { window in
            guard let scope = window.scope else { return false }
            return seenScopes.insert(scope).inserted
        }
        return primary + auxiliary
    }
}

struct WalletBalance: Codable, Equatable, Sendable {
    let currency: String
    let total: Decimal
    let granted: Decimal?
    let toppedUp: Decimal?
    /// False for non-currency units such as Poe points. They have no monetary reminder policy.
    let isMonetary: Bool

    init(currency: String, total: Decimal, granted: Decimal? = nil,
         toppedUp: Decimal? = nil, isMonetary: Bool = true) {
        self.currency = currency
        self.total = total
        self.granted = granted
        self.toppedUp = toppedUp
        self.isMonetary = isMonetary
    }

    private enum CodingKeys: String, CodingKey {
        case currency, total, granted, toppedUp, isMonetary
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currency = try values.decode(String.self, forKey: .currency)
        total = try values.decode(Decimal.self, forKey: .total)
        granted = try values.decodeIfPresent(Decimal.self, forKey: .granted)
        toppedUp = try values.decodeIfPresent(Decimal.self, forKey: .toppedUp)
        // Existing DeepSeek snapshots predate the unit classification.
        isMonetary = try values.decodeIfPresent(Bool.self, forKey: .isMonetary) ?? true
    }
}

enum QuotaDatePrecision: String, Codable, Sendable { case day }

enum QuotaResetSemantics: String, Codable, Sendable {
    case continuousReplenishment
    case nonResettingAllowance
}

/// Exact reported quantities. Percentages remain Double for UI gauges, never for stored counts.
struct DecimalQuotaCounts: Codable, Equatable, Sendable {
    let used: Decimal?
    let remaining: Decimal?
    let total: Decimal?

    init(used: Decimal? = nil, remaining: Decimal? = nil, total: Decimal? = nil) {
        self.used = used
        self.remaining = remaining
        self.total = total
    }
}

/// App-owned fallback provenance. Raw provider names and stable identity remain unchanged.
enum QuotaPresentationLabel: String, Codable, Equatable, Sendable {
    case monthlyTokenAllowance
    case extraAllowance
    case geminiModelGroup
    case providerModel
    case modelDisabled
}

enum QuotaPresentationUnit: String, Codable, Equatable, Sendable {
    case unspecifiedQuotaUnit
    case unspecifiedUnitType
}

/// Localized scope components retain the provider/user name as an uninterpreted value.
struct QuotaScopePresentation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case organization, project, team, user
        case apiKey = "api_key"
    }
    let kind: Kind?
    let name: String?
    let isShared: Bool
}

/// App-generated account descriptions, separate from actual provider plan/brand names.
enum QuotaPlanPresentation: Codable, Equatable, Sendable {
    case payAsYouGo
    case team(identifier: String)
}

struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let scope: String?
    let period: QuotaPeriod?
    let isExhausted: Bool?
    let isUnlimited: Bool
    let usedPercentage: Double?
    let remainingCount: Double?
    let totalCount: Double?
    let resetsAt: Date?
    /// Opaque stable identifier supplied by the provider. Never derive it from `resetsAt`.
    let cycleID: String?
    let unit: String?
    let expiresAt: Date?
    let wallet: WalletBalance?
    let overagePermitted: Bool?
    let overageCount: Double?
    /// Nil preserves the existing provider-window reset rules.
    let resetSemantics: QuotaResetSemantics?
    /// A partial refill time, never a complete reset or reset-notification schedule.
    let nextReplenishmentAt: Date?
    let exactCounts: DecimalQuotaCounts?
    /// nil preserves existing exact-time behavior; day stores a UTC calendar-date anchor.
    let resetDatePrecision: QuotaDatePrecision?
    /// Nil in legacy archives where provider text and an app fallback cannot be distinguished.
    let presentationLabel: QuotaPresentationLabel?
    let presentationUnit: QuotaPresentationUnit?
    let presentationScope: QuotaScopePresentation?

    init(id: String,
         name: String,
         scope: String?,
         period: QuotaPeriod? = nil,
         isExhausted: Bool? = nil,
         isUnlimited: Bool = false,
         usedPercentage: Double?,
         remainingCount: Double?,
         totalCount: Double?,
         resetsAt: Date?,
         cycleID: String? = nil,
         unit: String? = nil,
         expiresAt: Date? = nil,
         wallet: WalletBalance? = nil,
         overagePermitted: Bool? = nil,
         overageCount: Double? = nil,
         exactCounts: DecimalQuotaCounts? = nil,
         resetSemantics: QuotaResetSemantics? = nil,
         nextReplenishmentAt: Date? = nil,
         resetDatePrecision: QuotaDatePrecision? = nil,
         presentationLabel: QuotaPresentationLabel? = nil,
         presentationUnit: QuotaPresentationUnit? = nil,
         presentationScope: QuotaScopePresentation? = nil) {
        self.id = id
        self.name = name
        self.scope = scope
        self.period = period
        self.isExhausted = isExhausted
        self.isUnlimited = isUnlimited
        self.usedPercentage = usedPercentage
        self.remainingCount = remainingCount
        self.totalCount = totalCount
        self.resetsAt = resetsAt
        self.cycleID = cycleID
        self.unit = unit
        self.expiresAt = expiresAt
        self.wallet = wallet
        self.overagePermitted = overagePermitted
        self.overageCount = overageCount
        self.resetSemantics = resetSemantics
        self.nextReplenishmentAt = nextReplenishmentAt
        self.exactCounts = exactCounts
        self.resetDatePrecision = resetDatePrecision
        self.presentationLabel = presentationLabel
        self.presentationUnit = presentationUnit
        self.presentationScope = presentationScope
    }

    func needsUpdate(at date: Date) -> Bool {
        resetDatePrecision != .day && (resetsAt.map { $0 <= date } ?? false)
    }

    var hasDetailValues: Bool {
        wallet != nil || exactCounts?.used != nil || exactCounts?.remaining != nil || exactCounts?.total != nil
            || remainingCount != nil || totalCount != nil || resetsAt != nil || expiresAt != nil
            || nextReplenishmentAt != nil || isUnlimited || overagePermitted == true || isExhausted == true
    }

    var displayName: String {
        scope.map { "\($0) \(name)" } ?? name
    }
}

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let accountID: UUID
    var windows: [QuotaWindow]
    let collectedAt: Date
    var subscriptionPlan: SubscriptionPlan? = nil
    var remainingResetCount: Int? = nil
    var walletAvailable: Bool? = nil
    var quotaExceeded: Bool? = nil
    /// A one-way identity for web-session cache matching; never contains cookies.
    var sourceCredentialFingerprint: String? = nil
    var providerPlanName: String? = nil
    var providerPlanPresentation: QuotaPlanPresentation? = nil
    var walletCollectedAt: Date? = nil
    var walletFailure: RefreshFailure? = nil

    func retainingWalletAfterPartialFailure(from previous: QuotaSnapshot?) -> QuotaSnapshot {
        guard walletFailure != nil else { return self }
        var result = self
        result.windows.removeAll { $0.wallet != nil }
        result.walletCollectedAt = nil
        result.walletAvailable = nil
        guard let previous, previous.accountID == accountID,
              let identity = sourceCredentialFingerprint, identity == previous.sourceCredentialFingerprint else { return result }
        let wallets = previous.windows.filter { $0.wallet != nil }
        result.windows.append(contentsOf: wallets)
        if !wallets.isEmpty { result.walletCollectedAt = previous.walletCollectedAt ?? previous.collectedAt }
        result.walletAvailable = previous.walletAvailable
        return result
    }
    var isNoPlan: Bool? = nil
    /// Static provider-confirmed categorical status; never relay arbitrary server HTML.
    var quotaStatusText: String? = nil

    func windows(for provider: Provider, surface: QuotaSurface) -> [QuotaWindow] {
        QuotaPolicy.windows(windows, provider: provider, plan: subscriptionPlan, surface: surface)
    }
}

enum RefreshFailure: String, Codable, Equatable, Sendable, Error {
    case invalidCredential
    case managementKeyRequired
    case network
    case rateLimited
    case server
    case unreadableResponse
    case noQuotaWindows
    case subscriptionRequired
    case insufficientPermissions
    case googleClientUnsupported
    case googleProjectRequired
    case consoleSessionRequired

    var displayName: String { displayName(language: nil) }

    func displayName(language: String?) -> String {
        switch self {
        case .invalidCredential: L10n.text("凭证无效或已过期，请重新登录", language: language)
        case .managementKeyRequired: L10n.text("Management Key 无效或权限不足；普通推理 Key 无权查询", language: language)
        case .network: L10n.text("网络连接失败", language: language)
        case .rateLimited: L10n.text("请求过于频繁", language: language)
        case .server: L10n.text("提供商服务异常", language: language)
        case .unreadableResponse: L10n.text("无法读取额度响应", language: language)
        case .noQuotaWindows: L10n.text("未返回套餐额度窗口", language: language)
        case .subscriptionRequired: L10n.text("当前凭证没有可用的订阅套餐", language: language)
        case .insufficientPermissions: L10n.text("Key 缺少所需的查询权限，请检查权限设置", language: language)
        case .googleClientUnsupported: L10n.text("Google quota 服务不支持此 OAuth client，请检查客户端注册", language: language)
        case .googleProjectRequired: L10n.text("Google quota 访问被拒绝或项目未就绪，请检查 client、项目权限与账户资格", language: language)
        case .consoleSessionRequired: L10n.text("该接口要求控制台登录会话，当前 Key 无法查询；请在对应站点检查。", language: language)
        }
    }
}

struct AccountQuotaState: Codable, Equatable, Identifiable, Sendable {
    var account: SubscriptionAccount
    var snapshot: QuotaSnapshot?
    var lastFailure: RefreshFailure?
    var credentialIdentity: String? = nil

    var id: UUID { account.id }
}
