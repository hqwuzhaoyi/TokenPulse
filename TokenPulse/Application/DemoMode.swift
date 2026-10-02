import Foundation

/// All demo persistence stays in this device-local suite; credentials never leave memory.
enum DemoMode {
    static let enabledKey = "demoModeEnabled"
    static let suiteName = "com.tokenpulse.demo"
    static let proAccountID = UUID(uuidString: "DE000000-0000-0000-0000-000000000003")!

    static func accounts() -> [SubscriptionAccount] {
        let examples: [(Provider, String)] = [
            (.miniMaxChina, "MiniMax 国内版"), (.claude, "Claude"),
            (.codex, "Codex Pro"), (.codex, "Codex Plus"),
            (.openCodeGo, "OpenCode Go"), (.zai, "Z.ai"), (.superGrok, "SuperGrok"),
            (.qoderInternational, "Qoder 国际版"), (.deepSeek, "DeepSeek 钱包"),
            (.kimiCode, "Kimi Code 国内版"), (.elevenLabs, "ElevenLabs"),
            (.poe, "Poe points"), (.vercelAIGateway, "Vercel AI Gateway 钱包"),
            (.zhipu, "智谱国内版"), (.miniMaxInternational, "MiniMax 国际版"),
            (.stepFun, "StepFun Token Plan"), (.stepFun, "StepFun Coding Plan"),
            (.newAPI, "New API 钱包"),
        ]
        return examples.enumerated().map { index, example in
            SubscriptionAccount(
                id: UUID(uuidString: String(format: "DE000000-0000-0000-0000-%012d", index + 1))!,
                name: "演示 · \(example.1)", provider: example.0
            )
        }
    }

    @MainActor
    static func makeMonitor(suiteName: String = suiteName) -> QuotaMonitor {
        let defaults = UserDefaults(suiteName: suiteName)!
        let states = accounts().map {
            AccountQuotaState(account: $0, snapshot: snapshot(accountID: $0.id, provider: $0.provider))
        }
        if defaults.data(forKey: "accountQuotaStates") == nil {
            defaults.set(try? JSONEncoder().encode(states), forKey: "accountQuotaStates")
            defaults.set(try? JSONEncoder().encode(states.map { AccountConfiguration(account: $0.account) }),
                         forKey: "accountConfigurations")
        }
        let client = DemoQuotaClient(provider: .miniMaxChina)
        let clients = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, DemoQuotaClient(provider: $0)) })
        return QuotaMonitor(
            accountStore: LocalAccountStateStore(suiteName: suiteName),
            credentialStore: DemoCredentialStore(), quotaClient: client,
            configurationStore: LocalAccountConfigurationStore(suiteName: suiteName),
            providerClient: { clients[$0]! }
        )
    }

    static func snapshot(accountID: UUID, provider: Provider, revision: Int = 0, now: Date = Date()) -> QuotaSnapshot {
        func window(_ id: String, _ name: String, _ period: QuotaPeriod, _ usage: Double,
                    scope: String? = nil) -> QuotaWindow {
            let percentage = (usage + Double(revision * 9)).truncatingRemainder(dividingBy: 101)
            let duration: TimeInterval = switch period {
            case .fiveHour: 2 * 3_600
            case .weekly: 3 * 86_400
            case .monthly: 12 * 86_400
            case .other: 3_600
            }
            return QuotaWindow(
                id: id, name: name, scope: scope, period: period,
                usedPercentage: percentage, remainingCount: 1_000 - percentage * 10,
                totalCount: 1_000, resetsAt: now.addingTimeInterval(duration), cycleID: "demo-cycle"
            )
        }
        let short = window("demo.five-hour", "5 小时额度", .fiveHour, 36)
        let weekly = window("demo.weekly", "每周额度", .weekly, 71)
        let windows: [QuotaWindow] = switch provider {
        case .miniMaxChina: [short]
        case .claude: [short, weekly, window("demo.sonnet", "每周额度", .weekly, 24, scope: "Sonnet")]
        case .codex: [short, weekly, window("demo.spark", "5 小时额度", .fiveHour, 18, scope: "GPT-5.3-Codex-Spark")]
        case .openCodeGo: [short, weekly, window("demo.monthly", "每月额度", .monthly, 48)]
        case .kimiCode: [short, weekly, window("kimiCode.monthly", "每月总额度", .monthly, 48)]
        case .zai, .zhipu, .miniMaxInternational: [short, weekly]
        case .superGrok: [window("superGrok.pool", "每周额度", .weekly, 62)]
        case .qoderInternational: [
            QuotaWindow(id: "qoder.userQuota", name: "个人额度", scope: nil,
                        usedPercentage: 25, remainingCount: 2250, totalCount: 3000, resetsAt: nil,
                        unit: "credits", expiresAt: now.addingTimeInterval(12 * 86_400)),
            QuotaWindow(id: "qoder.orgResourcePackage", name: "组织资源包", scope: nil,
                        usedPercentage: 40, remainingCount: 600, totalCount: 1000, resetsAt: nil,
                        unit: "credits")
        ]
        case .elevenLabs: [
            QuotaWindow(id: "elevenlabs.characters", name: "账期字符额度", scope: nil,
                        usedPercentage: 36 + Double(revision % 5) * 9,
                        remainingCount: 64_000 - Double(revision % 5) * 9_000, totalCount: 100_000,
                        resetsAt: now.addingTimeInterval(12 * 86_400), unit: "字符")
        ]
        case .poe: [
            QuotaWindow(id: "poe.points", name: "剩余 points", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "points", total: Decimal(125_000 - revision * 100),
                                              isMonetary: false))
        ]
        case .vercelAIGateway: [
            QuotaWindow(id: "vercelAIGateway.wallet.USD", name: "API 钱包余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: Decimal(string: "12.3456789")!))
        ]
        case .stepFun:
            accountID == accounts().last(where: { $0.provider == .stepFun })?.id ? [short, weekly] : [
                QuotaWindow(id: "stepfun.credits", name: "Token Plan 积分额度", scope: nil, period: .other,
                            usedPercentage: 25, remainingCount: 1_200_000_000, totalCount: 1_600_000_000,
                            resetsAt: nil, unit: "积分", expiresAt: now.addingTimeInterval(3 * 86_400))
            ]
        case .newAPI: [
            QuotaWindow(id: "newAPI.balance", name: "API 钱包余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: 13.155))
        ]
        case .deepSeek: [
            QuotaWindow(id: "deepseek.CNY", name: "API 钱包余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "CNY", total: 110, granted: 10, toppedUp: 100)),
            QuotaWindow(id: "deepseek.USD", name: "API 钱包余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: 8, granted: 1, toppedUp: 7))
        ]
        }
        return QuotaSnapshot(
            accountID: accountID, windows: windows, collectedAt: now,
            subscriptionPlan: provider == .codex ? (accountID == proAccountID ? .pro : .plus) : nil,
            remainingResetCount: provider == .codex || provider == .superGrok ? 2 : nil,
            walletAvailable: provider == .deepSeek ? true : nil
        )
    }
}

private struct DemoCredentialStore: CredentialStoring {
    func save(_ credential: String, for accountID: UUID) async throws {}
    func credential(for accountID: UUID) async throws -> String? { "demo" }
    func deleteCredential(for accountID: UUID) async throws {}
}

private actor DemoQuotaClient: QuotaQuerying {
    let provider: Provider
    private var revisions: [UUID: Int] = [:]

    init(provider: Provider) { self.provider = provider }

    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        revisions[accountID, default: 0] += 1
        return DemoMode.snapshot(accountID: accountID, provider: provider, revision: revisions[accountID]!)
    }
}
