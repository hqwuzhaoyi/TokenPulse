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
    case copilot
    case clinePass
    case clawRouter
    case aixy
    case neuralwatt
    case codebuff
    case moonshot
    case factory
    case venice
    case hyper
    case deepInfra
    case kiloCode
    case atlasCloud
    case commandCode, amp, gitKraken, huggingFace
    case synthetic, v2ex, xKiro, zenMux
    case alibabaCodingPlan, chutes, cursor
    case volcengine
    case xaiAPI
    case ibmBob
    case warp, v0, devPass
    case raycastAI, t3Chat, zoomMate, qwenCloud, typeSafe

    var id: String { rawValue }
    var requiresRegion: Bool { self == .moonshot || self == .alibabaCodingPlan }
    var hasMonetaryWallet: Bool { [.typeSafe, .xaiAPI, .xKiro, .zenMux, .commandCode, .amp, .neuralwatt, .deepSeek, .vercelAIGateway, .newAPI, .moonshot, .atlasCloud, .kiloCode, .deepInfra, .venice].contains(self) }
    var hasWalletBalance: Bool { hasMonetaryWallet || [.poe, .codebuff, .hyper].contains(self) }
    var balancePresentation: ProviderBalancePresentation {
        switch self {
        case .deepSeek, .vercelAIGateway, .newAPI, .poe, .moonshot, .atlasCloud, .hyper, .venice, .xaiAPI, .typeSafe: .walletOnly
        case .xKiro, .zenMux, .commandCode, .amp, .codebuff, .neuralwatt, .kiloCode, .deepInfra: .mixed
        default: .none
        }
    }
    var displayName: String {
        switch self {
        case .miniMaxChina: "MiniMax 国内版"
        case .miniMaxInternational: "MiniMax 国际版"
        case .zhipu: "智谱国内版"
        case .claude: "Claude"
        case .codex: "Codex"
        case .openCodeGo: "OpenCode Go"
        case .zai: "Z.ai"
        case .superGrok: "SuperGrok"
        case .qoderInternational: "Qoder 国际版"
        case .deepSeek: "DeepSeek"
        case .poe: "Poe"
        case .vercelAIGateway: "Vercel AI Gateway"
        case .kimiCode: "Kimi Code 国内版"
        case .elevenLabs: "ElevenLabs"
        case .stepFun: "StepFun"
        case .newAPI: "New API"
        case .copilot: "GitHub Copilot"
        case .clinePass: "ClinePass"
        case .clawRouter: "ClawRouter"
        case .aixy: "Aixy"
        case .neuralwatt: "Neuralwatt"
        case .codebuff: "Codebuff"
        case .moonshot: "Moonshot API 钱包"
        case .factory: "Factory"
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
        case .alibabaCodingPlan: "阿里百炼 Coding Plan"
        case .chutes: "Chutes"
        case .cursor: "Cursor"
        case .volcengine: "火山方舟"
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
        }
    }
}
/// Region is an explicit credential choice, never inferred by trying another host.
enum ProviderRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case china, international
    var id: String { rawValue }
    var displayName: String { self == .china ? "国内（中国）" : "国际" }
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
         resetDatePrecision: QuotaDatePrecision? = nil) {
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
    case consoleSessionRequired

    var displayName: String {
        switch self {
        case .invalidCredential: "凭证无效或已过期，请重新登录"
        case .managementKeyRequired: "Management Key 无效或权限不足；普通推理 Key 无权查询"
        case .network: "网络连接失败"
        case .rateLimited: "请求过于频繁"
        case .server: "提供商服务异常"
        case .unreadableResponse: "无法读取额度响应"
        case .noQuotaWindows: "未返回套餐额度窗口"
        case .subscriptionRequired: "当前凭证没有可用的订阅套餐"
        case .insufficientPermissions: "Key 缺少所需的查询权限，请检查权限设置"
        case .consoleSessionRequired: "该接口要求控制台登录会话，当前 Key 无法查询；请在对应站点检查。"
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
