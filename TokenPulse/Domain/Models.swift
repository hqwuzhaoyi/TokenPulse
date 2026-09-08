import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case miniMaxChina
    case claude, codex, zai, superGrok

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .miniMaxChina: "MiniMax 国内版"
        case .claude: "Claude"
        case .codex: "Codex"
        case .zai: "Z.ai"
        case .superGrok: "SuperGrok"
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

struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let scope: String?
    let isUnlimited: Bool
    let usedPercentage: Double?
    let remainingCount: Double?
    let totalCount: Double?
    let resetsAt: Date?
    let cycleID: String?

    init(id: String,
         name: String,
         scope: String?,
         isUnlimited: Bool = false,
         usedPercentage: Double?,
         remainingCount: Double?,
         totalCount: Double?,
         resetsAt: Date?,
         cycleID: String? = nil) {
        self.id = id
        self.name = name
        self.scope = scope
        self.isUnlimited = isUnlimited
        self.usedPercentage = usedPercentage
        self.remainingCount = remainingCount
        self.totalCount = totalCount
        self.resetsAt = resetsAt
        self.cycleID = cycleID
    }

    func needsUpdate(at date: Date) -> Bool {
        resetsAt.map { $0 <= date } ?? false
    }
}

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let accountID: UUID
    let windows: [QuotaWindow]
    let collectedAt: Date
    var remainingResetCount: Int? = nil
}

enum RefreshFailure: String, Codable, Equatable, Sendable, Error {
    case invalidCredential
    case network
    case rateLimited
    case server
    case unreadableResponse
    case noQuotaWindows

    var displayName: String {
        switch self {
        case .invalidCredential: "凭证无效或已过期，请重新登录"
        case .network: "网络连接失败"
        case .rateLimited: "请求过于频繁"
        case .server: "提供商服务异常"
        case .unreadableResponse: "无法读取额度响应"
        case .noQuotaWindows: "未返回套餐额度窗口"
        }
    }
}

struct AccountQuotaState: Codable, Equatable, Identifiable, Sendable {
    var account: SubscriptionAccount
    var snapshot: QuotaSnapshot?
    var lastFailure: RefreshFailure?

    var id: UUID { account.id }
}
