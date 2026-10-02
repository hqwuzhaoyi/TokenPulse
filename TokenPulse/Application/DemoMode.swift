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
            (.copilot, "GitHub Copilot Free"), (.clinePass, "ClinePass"),
            (.clawRouter, "ClawRouter"),
            (.aixy, "Aixy"),
            (.neuralwatt, "Neuralwatt"),
            (.codebuff, "Codebuff"),
            (.moonshot, "Moonshot 国内 API 钱包"), (.moonshot, "Moonshot 国际 API 钱包"),
            (.factory, "Factory Standard / Core"), (.factory, "Factory Standard / Premium"),
            (.atlasCloud, "Atlas Cloud"),
            (.kiloCode, "Kilo Code"),
            (.deepInfra, "DeepInfra"),
            (.hyper, "Hyper"),
            (.venice, "Venice"),
            (.commandCode, "Command Code"),
            (.amp, "Amp"),
            (.gitKraken, "GitKraken AI"),
            (.huggingFace, "Hugging Face ZeroGPU"),
            (.synthetic, "Synthetic"), (.v2ex, "V2EX"), (.xKiro, "xKiro"), (.zenMux, "ZenMux"),
            (.alibabaCodingPlan, "百炼 Coding Plan"), (.chutes, "Chutes 订阅预算"), (.cursor, "Cursor 模型池"),
            (.volcengine, "火山方舟"), (.xaiAPI, "xAI API 团队余额"), (.ibmBob, "IBM Bob 团队预算"),
            (.warp, "Warp"), (.v0, "v0"), (.devPass, "DevPass"),
            (.abacus, "Abacus AI"),
            (.perplexity, "Perplexity API"),
            (.notionAI, "Notion AI"),
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
        case .openCodeGo, .clinePass: [short, weekly, window("demo.monthly", "每月额度", .monthly, 48)]
        case .factory: accountID == accounts().first(where: { $0.name.contains("Standard / Premium") })?.id
            ? [window("factory.legacy.standard", "每月额度", .monthly, 35, scope: "Standard"),
               window("factory.legacy.premium", "每月额度", .monthly, 70, scope: "Premium")]
            : [window("factory.rate.standard.fiveHour", "5 小时额度", .fiveHour, 35, scope: "Standard"),
               window("factory.rate.standard.weekly", "每周额度", .weekly, 70, scope: "Standard"),
               window("factory.rate.core.weekly", "每周额度", .weekly, 25, scope: "Core"),
               QuotaWindow(id: "factory.extraUsage", name: "附加用量余额", scope: nil, usedPercentage: nil,
                           remainingCount: 2500, totalCount: nil, resetsAt: nil, unit: "cents（币种未提供）")]
        case .zenMux: [
            QuotaWindow(id: "zenmux.five_hour", name: "5 小时额度", scope: nil, period: .fiveHour, usedPercentage: 7.15,
                        remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(7200)),
            QuotaWindow(id: "zenmux.seven_day", name: "每周额度", scope: nil, period: .weekly, usedPercentage: 6.73,
                        remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(172800)),
            QuotaWindow(id: "zenmux.wallet", name: "按量钱包余额", scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: Decimal(string: "482.74")!))
        ]
        case .xKiro: [
            QuotaWindow(id: "xkiro.short", name: "5 小时额度", scope: nil, period: .fiveHour,
                        usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(5005), unit: "USD 预算额度",
                        exactCounts: DecimalQuotaCounts(used: 50, remaining: 150, total: 200)),
            QuotaWindow(id: "xkiro.long", name: "每周额度", scope: nil, period: .weekly,
                        usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(199405), unit: "USD 预算额度",
                        exactCounts: DecimalQuotaCounts(used: 330, remaining: 990, total: 1320)),
            QuotaWindow(id: "xkiro.free_tokens", name: "每日免费 tokens", scope: nil, period: .other,
                        usedPercentage: 0.13734333, remainingCount: 299_587_970, totalCount: 300_000_000, resetsAt: XKiroProviderClient.nextMidnightUTC(after: now), unit: "tokens"),
            QuotaWindow(id: "xkiro.wallet", name: "API 钱包余额", scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: Decimal(string: "683.95")!))
        ]
        case .v2ex: [
            QuotaWindow(id: "v2ex.five_hour", name: "5 小时额度", scope: nil, period: .fiveHour,
                        usedPercentage: 25, remainingCount: 6_015_000, totalCount: 8_020_000,
                        resetsAt: now.addingTimeInterval(7200), cycleID: "demo-v2ex-start", unit: "tokens"),
            QuotaWindow(id: "v2ex.extra", name: "额外用量补充包", scope: nil, period: .other,
                        usedPercentage: 5, remainingCount: 11_400_000, totalCount: 12_000_000, resetsAt: nil,
                        unit: "tokens", resetSemantics: .nonResettingAllowance)
        ]
        case .synthetic: [
            QuotaWindow(id: "synthetic.five_hour", name: "5 小时滚动额度", scope: nil, period: .fiveHour,
                        usedPercentage: 20, remainingCount: 600, totalCount: 750, resetsAt: nil,
                        resetSemantics: .continuousReplenishment, nextReplenishmentAt: now.addingTimeInterval(300)),
            QuotaWindow(id: "synthetic.weekly", name: "每周滚动额度", scope: nil, period: .weekly,
                        usedPercentage: 2, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        resetSemantics: .continuousReplenishment, nextReplenishmentAt: now.addingTimeInterval(600)),
            QuotaWindow(id: "synthetic.search_hourly", name: "每小时额度", scope: "Search", period: .other,
                        usedPercentage: 10, remainingCount: 225, totalCount: 250, resetsAt: now.addingTimeInterval(1800), unit: "次请求")
        ]
        case .ibmBob: [
            QuotaWindow(id: "ibmBob.personal.solo.user", name: "Bobcoins", scope: "Personal · Solo", period: .monthly,
                        usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(10 * 86_400), unit: "Bobcoins",
                        exactCounts: DecimalQuotaCounts(used: 10, remaining: 30, total: 40)),
            QuotaWindow(id: "ibmBob.work.platform.user", name: "Bobcoins（预算未提供）", scope: "Work · Platform", period: .monthly,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(20 * 86_400), unit: "Bobcoins",
                        exactCounts: DecimalQuotaCounts(used: 12.5))
        ]
        case .xaiAPI: [
            QuotaWindow(id: "xaiAPI.team.demo.wallet.USD", name: "已入账预付余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "USD", wallet: WalletBalance(currency: "USD", total: 12.34))
        ]
        case .volcengine: [
            window("volcengine.coding.fiveHour", "5 小时额度", .fiveHour, 12, scope: "Coding Plan"),
            window("volcengine.coding.weekly", "每周额度", .weekly, 41.5, scope: "Coding Plan"),
            QuotaWindow(id: "volcengine.agent.fiveHour", name: "5 小时额度", scope: "Agent Plan", period: .fiveHour,
                        usedPercentage: 25, remainingCount: 750, totalCount: 1000, resetsAt: now.addingTimeInterval(3600), unit: "AFP")
        ]
        case .devPass: [
            QuotaWindow(id: "devpass.premium_weekly", name: "Premium 每周额度", scope: nil, period: .weekly,
                        usedPercentage: 50, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(3 * 86400),
                        unit: "USD credits", exactCounts: .init(used: 5, remaining: 5, total: 10)),
            QuotaWindow(id: "devpass.cycle", name: "账期 credits", scope: nil, period: .other,
                        usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "USD credits", exactCounts: .init(used: 25, remaining: 75, total: 100)),
            QuotaWindow(id: "devpass.key_limit", name: "Key 累计限额", scope: nil, period: .other,
                        usedPercentage: 40, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "USD credits", exactCounts: .init(used: 40, remaining: 60, total: 100), resetSemantics: .nonResettingAllowance)
        ]
        case .v0: [
            QuotaWindow(id: "v0.billing", name: "账期 credits", scope: nil, period: .other,
                        usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(12 * 86400),
                        unit: "credits", exactCounts: .init(used: 250, remaining: 750, total: 1000)),
            QuotaWindow(id: "v0.rate_limit", name: "消息限流", scope: nil, period: .other,
                        usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(1800),
                        unit: "条消息", exactCounts: .init(used: 20, remaining: 80, total: 100))
        ]
        case .warp: [
            QuotaWindow(id: "warp.plan", name: "套餐 credits", scope: nil, period: .other,
                        usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(12 * 86400),
                        unit: "credits", exactCounts: .init(used: 625, remaining: 1875, total: 2500)),
            QuotaWindow(id: "warp.grant.demo.personal", name: "个人 附加 credits 1", scope: nil, period: .other,
                        usedPercentage: 60, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "credits", expiresAt: now.addingTimeInterval(4 * 86400), exactCounts: .init(used: 600, remaining: 400, total: 1000), resetSemantics: .nonResettingAllowance),
            QuotaWindow(id: "warp.grant.demo.workspace", name: "工作区 1 附加 credits 1", scope: nil, period: .other,
                        usedPercentage: 0, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "credits", expiresAt: now.addingTimeInterval(20 * 86400), exactCounts: .init(used: 0, remaining: 500, total: 500), resetSemantics: .nonResettingAllowance)
        ]
        case .copilot: [
            window("copilot.premium_interactions", "Premium requests", .monthly, 60),
            window("copilot.chat", "Chat", .monthly, 30),
            window("copilot.completions", "Completions", .monthly, 20)
        ]
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
        case .moonshot: [
            QuotaWindow(id: "moonshot.demo.wallet", name: "API 钱包余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: accountID == accounts().last(where: { $0.provider == .moonshot })?.id ? "USD" : "CNY",
                                              total: Decimal(50 - revision), granted: 10, toppedUp: 40))
        ]
        case .codebuff: [
            QuotaWindow(id: "codebuff.credits", name: "credits 额度", scope: nil, usedPercentage: 35,
                remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(86400), unit: "credits",
                exactCounts: .init(used: 350, remaining: 650, total: 1000)),
            QuotaWindow(id: "codebuff.balance", name: "剩余 credits", scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: WalletBalance(currency: "credits", total: 650, isMonetary: false))
        ]
        case .neuralwatt: [
            QuotaWindow(id: "neuralwatt.subscription", name: "订阅能量额度", scope: nil, period: .monthly,
                usedPercentage: 40, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(86400),
                unit: "kWh", exactCounts: .init(used: 4, remaining: 6, total: 10)),
            QuotaWindow(id: "neuralwatt.key", name: "Key 支出限额", scope: nil, usedPercentage: 25,
                remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "USD",
                exactCounts: .init(used: 5, remaining: 15, total: 20)),
            QuotaWindow(id: "neuralwatt.wallet", name: "API 钱包余额", scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: WalletBalance(currency: "USD", total: 15))
        ]
        case .aixy: [
            QuotaWindow(id: "aixy.team", name: "每月预算", scope: "团队 · 共享", period: .monthly,
                usedPercentage: 80, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(86400),
                unit: "USD", exactCounts: .init(used: 80, remaining: 20, total: 100)),
            QuotaWindow(id: "aixy.key", name: "每月监控预算", scope: "Key", period: .monthly,
                usedPercentage: 60, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(86400),
                unit: "USD", exactCounts: .init(used: 12, remaining: 8, total: 20))
        ]
        case .clawRouter: [
            QuotaWindow(id: "clawRouter.monthly", name: "每月预算", scope: nil, period: .monthly,
                usedPercentage: 35, remainingCount: nil, totalCount: nil, resetsAt: nil,
                cycleID: "demo-claw-budget", unit: "USD", exactCounts: .init(used: 7, remaining: 13, total: 20))
        ]
        case .atlasCloud: [WalletExpansionHTTP.walletWindow(id: "atlasCloud.wallet.USD", wallet: WalletBalance(currency: "USD", total: Decimal(string: "42.50")!))]
        case .kiloCode: [WalletExpansionHTTP.walletWindow(id: "kiloCode.wallet.USD", wallet: WalletBalance(currency: "USD", total: Decimal(string: "12.75")!)), QuotaWindow(id: "kiloCode.pass", name: "Kilo Pass 当期额度", scope: nil, period: .other, usedPercentage: 25, remainingCount: 21.375, totalCount: 28.5, resetsAt: now.addingTimeInterval(12 * 86_400), unit: "USD")]
        case .deepInfra: [WalletExpansionHTTP.walletWindow(id: "deepInfra.wallet.USD", wallet: WalletBalance(currency: "USD", total: Decimal(string: "95.81")!)), QuotaWindow(id: "deepInfra.spend", name: "支出上限", scope: nil, period: .other, usedPercentage: 19.7, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "USD", exactCounts: DecimalQuotaCounts(used: Decimal(string: "3.94")!, remaining: Decimal(string: "16.06")!, total: 20))]
        case .hyper: [WalletExpansionHTTP.walletWindow(id: "hyper.HC", wallet: WalletBalance(currency: "HC", total: Decimal(string: "1234.5")!, isMonetary: false))]
        case .venice: [WalletExpansionHTTP.walletWindow(id: "venice.balance.DIEM", wallet: WalletBalance(currency: "DIEM", total: Decimal(string: "90.5")!, isMonetary: false))]
        case .huggingFace: [
            QuotaWindow(id: "huggingFace.zeroGPU", name: "GPU time quota", scope: "ZeroGPU",
                        usedPercentage: 25, remainingCount: 1800, totalCount: 2400,
                        resetsAt: now.addingTimeInterval(8 * 3_600), unit: "GPU s")
        ]
        case .gitKraken: [
            QuotaWindow(id: "gitKraken.personal", name: "Personal AI credits", scope: nil,
                        usedPercentage: 25, remainingCount: 75, totalCount: 100,
                        resetsAt: now.addingTimeInterval(3 * 86_400), unit: "credits"),
            QuotaWindow(id: "gitKraken.organization", name: "Organization AI credits", scope: "Demo Organization",
                        usedPercentage: 40, remainingCount: 600, totalCount: 1000,
                        resetsAt: now.addingTimeInterval(3 * 86_400), unit: "credits")
        ]
        case .amp: [
            QuotaWindow(id: "amp.free", name: "Amp Free · 逐小时补充", scope: nil,
                        usedPercentage: 40, remainingCount: 6, totalCount: 10, resetsAt: nil, unit: "USD",
                        resetSemantics: .continuousReplenishment),
            QuotaWindow(id: "amp.orb", name: "Orb 账期额度", scope: nil, period: .monthly,
                        usedPercentage: 20, remainingCount: 600, totalCount: 750,
                        resetsAt: Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400 + 12 * 86_400),
                        unit: "小时", resetDatePrecision: .day),
            QuotaWindow(id: "amp.wallet.USD", name: "个人美元余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: Decimal(string: "10.205")!))
        ]
        case .commandCode: [
            QuotaWindow(id: "commandCode.five-hour", name: "5 小时消费限额", scope: nil, period: .fiveHour,
                        usedPercentage: 40, remainingCount: 12, totalCount: 20,
                        resetsAt: now.addingTimeInterval(2 * 3_600), unit: "USD"),
            QuotaWindow(id: "commandCode.wallet.USD", name: "可用美元余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: Decimal(string: "18.25")!))
        ]
        case .cursor: [
            window("cursor.cursorModels", "每月额度", .monthly, 12, scope: "Cursor Models"),
            window("cursor.otherModels", "每月额度", .monthly, 71, scope: "Other Models"),
            QuotaWindow(id: "cursor.onDemand", name: "额外支出额度", scope: nil, period: .monthly,
                        usedPercentage: 25, remainingCount: 15, totalCount: 20,
                        resetsAt: now.addingTimeInterval(12 * 86400), unit: "USD 预算",
                        exactCounts: DecimalQuotaCounts(used: 5, remaining: 15, total: 20))
        ]
        case .chutes: [
            QuotaWindow(id: "chutes.fourHour", name: "4 小时固定额度", scope: nil, period: .other,
                        usedPercentage: 40, remainingCount: 5, totalCount: 8.333333333333334,
                        resetsAt: now.addingTimeInterval(3600), unit: "USD 预算",
                        exactCounts: DecimalQuotaCounts(used: Decimal(string: "3.333333333333334")!, remaining: 5,
                                                       total: Decimal(string: "8.333333333333334")!)),
            QuotaWindow(id: "chutes.monthly", name: "账期额度", scope: nil, period: .monthly,
                        usedPercentage: 25, remainingCount: 75, totalCount: 100,
                        resetsAt: now.addingTimeInterval(12 * 86400), unit: "USD 预算",
                        exactCounts: DecimalQuotaCounts(used: 25, remaining: 75, total: 100))
        ]
        case .alibabaCodingPlan: [short, weekly, window("alibabaCodingPlan.monthly", "账期额度", .monthly, 48)]
        case .abacus: [QuotaWindow(id: "abacus.computePoints", name: "Compute points 额度", scope: nil, period: .other, usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(15 * 86_400), unit: "compute points", exactCounts: .init(used: 250, remaining: 750, total: 1000))]
        case .perplexity: [QuotaWindow(id: "perplexity.apiCredits.USD", name: "API credits 余额", scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: .init(currency: "USD", total: Decimal(string: "3.20")!))]
        case .notionAI: [QuotaWindow(id: "notionAI.demo.rolling", name: "Demo workspace · 6 小时 AI 额度", scope: nil, period: .other, usedPercentage: 42.5, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(3 * 3600), unit: "AI credits", exactCounts: .init(used: Decimal(string: "42.5")!, remaining: Decimal(string: "57.5")!, total: 100)), QuotaWindow(id: "notionAI.demo.billing", name: "Demo workspace · 账期 AI 额度", scope: nil, period: .monthly, usedPercentage: 18, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(15 * 86400), unit: "AI credits", exactCounts: .init(used: 18, remaining: 82, total: 100))]
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
            walletAvailable: provider == .deepSeek ? true : nil,
            providerPlanName: provider == .copilot ? "Free" : nil
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
