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
    case v0
    case devPass
    case factory

    var id: String { rawValue }
    var hasMonetaryWallet: Bool { self == .deepSeek || self == .vercelAIGateway || self == .newAPI }
    var hasWalletBalance: Bool { hasMonetaryWallet || self == .poe }
    var balancePresentation: ProviderBalancePresentation {
        switch self {
        case .deepSeek, .vercelAIGateway, .newAPI, .poe: .walletOnly
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
        case .v0: "v0"
        case .devPass: "DevPass"
        case .factory: "Factory"
        }
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

/// Exact reported quantities. Percentages remain Double for UI gauges, never for stored counts.
struct DecimalQuotaCounts: Codable, Equatable, Sendable {
    let used: Decimal
    let remaining: Decimal
    let total: Decimal
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
    let exactCounts: DecimalQuotaCounts?

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
         exactCounts: DecimalQuotaCounts? = nil) {
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
        self.exactCounts = exactCounts
    }

    func needsUpdate(at date: Date) -> Bool {
        resetsAt.map { $0 <= date } ?? false
    }

    var displayName: String {
        scope.map { "\($0) \(name)" } ?? name
    }
}

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let accountID: UUID
    let windows: [QuotaWindow]
    let collectedAt: Date
    var subscriptionPlan: SubscriptionPlan? = nil
    var remainingResetCount: Int? = nil
    var walletAvailable: Bool? = nil
    var quotaExceeded: Bool? = nil
    /// A one-way identity for web-session cache matching; never contains cookies.
    var sourceCredentialFingerprint: String? = nil
    var providerPlanName: String? = nil
    var isNoPlan: Bool? = nil

    func windows(for provider: Provider, surface: QuotaSurface) -> [QuotaWindow] {
        QuotaPolicy.windows(windows, provider: provider, plan: subscriptionPlan, surface: surface)
    }
}

enum RefreshFailure: String, Codable, Equatable, Sendable, Error {
    case invalidCredential
    case network
    case rateLimited
    case server
    case unreadableResponse
    case noQuotaWindows
    case subscriptionRequired
    case insufficientPermissions

    var displayName: String {
        switch self {
        case .invalidCredential: "凭证无效或已过期，请重新登录"
        case .network: "网络连接失败"
        case .rateLimited: "请求过于频繁"
        case .server: "提供商服务异常"
        case .unreadableResponse: "无法读取额度响应"
        case .noQuotaWindows: "未返回套餐额度窗口"
        case .subscriptionRequired: "当前凭证没有可用的订阅套餐"
        case .insufficientPermissions: "Key 缺少所需的查询权限，请检查权限设置"
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
