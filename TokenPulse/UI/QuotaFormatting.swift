import Foundation

enum QuotaFormatting {
    static func walletCollectionStatus(failure: RefreshFailure?, collectedAt: Date?) -> String? {
        guard failure != nil || collectedAt != nil else { return nil }
        if let failure {
            if let collectedAt {
                return L10n.format("钱包为旧数据（采集于 %@）；刷新失败：%@。", resetDate(collectedAt), failure.displayName)
            }
            return L10n.format("钱包刷新失败：%@。暂无成功钱包数据。", failure.displayName)
        }
        return collectedAt.map { L10n.format("钱包采集于 %@", resetDate($0)) }
    }

    static func remainingResets(_ count: Int?, language: String? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        guard let count else { return L10n.text("未提供", language: language) }
        return L10n.format("%lld 次", Int64(count), language: language, locale: locale)
    }

    static func resetDate(_ date: Date?, locale: Locale = .autoupdatingCurrent,
                          timeZone: TimeZone = .autoupdatingCurrent,
                          precision: QuotaDatePrecision? = nil) -> String {
        guard let date else { return L10n.text("未提供") }
        let formatter = DateFormatter()
        if precision == .day {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
        } else {
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    static func nextEventDate(_ window: QuotaWindow) -> Date? {
        [window.expiresAt, window.resetsAt, window.nextReplenishmentAt].compactMap { $0 }.min()
    }

    static func nextEventValue(_ window: QuotaWindow) -> String {
        let event = nextEventDate(window)
        if event == nil, window.resetSemantics == .continuousReplenishment { return L10n.text("持续补充") }
        if event == nil, window.resetSemantics == .nonResettingAllowance { return L10n.text("无周期重置") }
        return resetDate(event, precision: event == window.resetsAt ? window.resetDatePrecision : nil)
    }

    static func nextEventLabel(_ window: QuotaWindow) -> String {
        if nextEventDate(window) == nil, window.resetSemantics == .continuousReplenishment { return L10n.text("额度补充") }
        if nextEventDate(window) == nil, window.resetSemantics == .nonResettingAllowance { return L10n.text("额度类型") }
        if let replenishment = window.nextReplenishmentAt,
           nextEventDate(window) == replenishment { return L10n.text("下次补充") }
        guard let expiry = window.expiresAt else { return L10n.text("下次重置") }
        return L10n.text(window.resetsAt.map { $0 < expiry } == true ? "下次重置"
            : window.id == "stepfun.credits" ? "最早积分到期" : "到期时间")
    }

    static func percentage(_ value: Double?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let value, value.isFinite else { return L10n.text("未提供") }
        return L10n.format("%@ 已用", (value / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(locale)))
    }

    static func usage(_ window: QuotaWindow) -> String {
        if window.isUnlimited { return L10n.text("无限") }
        if let overage = overageDescription(window) { return overage }
        if window.isExhausted == true { return L10n.text("已用尽") }
        if let value = exactCountSummary(window) { return value }
        if window.unit != nil, window.remainingCount != nil || window.totalCount != nil {
            if let remaining = window.remainingCount, let total = window.totalCount {
                let values = L10n.format("%@ / %@", count(remaining, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2), count(total, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2))
                return withUnit(values, unit: L10n.windowUnit(window))
            }
            return count(window.remainingCount ?? window.totalCount, window: window)
        }
        return percentage(window.usedPercentage)
    }

    static func overageDescription(_ window: QuotaWindow) -> String? {
        guard !window.isUnlimited, window.isExhausted != true, window.overagePermitted == true,
              (window.usedPercentage ?? 0) >= 100 || (window.overageCount ?? 0) > 0 else { return nil }
        if let count = window.overageCount, count > 0 {
            return L10n.format("超额付费 %@", Self.count(count, window: window))
        }
        return L10n.text("可超额付费")
    }

    static func totalLabel(_ window: QuotaWindow) -> String {
        let family = window.id.components(separatedBy: ".").first ?? ""
        let isBudget = window.wallet == nil &&
            (["USD 预算", "USD 预算额度"].contains(window.unit ?? "") ||
             ["aixy", "clawRouter", "commandCode"].contains(family) || window.id == "neuralwatt.key")
        return L10n.text(isBudget ? "预算" : "总量")
    }

    static func effectiveUsedPercentage(_ window: QuotaWindow) -> Double? {
        guard window.wallet == nil, !window.isUnlimited else { return nil }
        return window.isExhausted == true ? 100 : window.usedPercentage
    }

    static func exactCountSummary(_ window: QuotaWindow) -> String? {
        guard let counts = window.exactCounts else { return nil }
        let values: String
        if let remaining = counts.remaining, let total = counts.total {
            values = "\(count(remaining)) / \(count(total))"
        } else if let used = counts.used, let total = counts.total {
            values = L10n.format("已用 %@ / %@", count(used), count(total))
        } else if let used = counts.used, let remaining = counts.remaining {
            values = L10n.format("已用 %@ · 剩余 %@", count(used), count(remaining))
        } else if let used = counts.used {
            return L10n.format("已用 %@", count(used, window: window))
        } else if let remaining = counts.remaining {
            return L10n.format("剩余 %@", count(remaining, window: window))
        } else if let total = counts.total {
            return L10n.format("总量 %@", count(total, window: window))
        } else { return nil }
        return withUnit(values, unit: L10n.windowUnit(window))
    }

    static func count(_ value: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(0...38)).locale(locale))
    }

    static func count(_ value: Decimal, unit: String?) -> String {
        let formatted = count(value)
        return withUnit(formatted, unit: unit)
    }

    static func count(_ value: Double?, maximumFractionDigits: Int = 2, locale: Locale = .autoupdatingCurrent) -> String {
        guard let value else { return L10n.text("未提供") }
        return value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)).locale(locale))
    }

    static func count(_ value: Double?, unit: String?) -> String {
        guard let value else { return L10n.text("未提供") }
        return withUnit(count(value, maximumFractionDigits: unit == "USD 预算额度" ? 6 : 2), unit: unit)
    }

    static func money(_ value: Decimal?, currency: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard let value else { return L10n.text("未提供") }
        return money(value, currency: currency, locale: locale)
    }

    static func balance(_ value: Decimal?, wallet: WalletBalance, locale: Locale = .autoupdatingCurrent) -> String {
        guard let value else { return L10n.text("未提供") }
        return money(value, currency: balanceUnit(wallet), locale: locale)
    }

    static func money(_ value: Decimal, currency: String, locale: Locale = .autoupdatingCurrent) -> String {
        let minimumFixedUnit = Decimal(string: "0.00000001")!
        let formatted: String
        if value != 0, value > -minimumFixedUnit, value < minimumFixedUnit {
            formatted = value.formatted(.number.notation(.scientific).precision(.significantDigits(1...8)).locale(locale))
        } else {
            formatted = value.formatted(.number.precision(.fractionLength(0...8)).locale(locale))
        }
        return "\(formatted) \(currency)"
    }

    static func balanceUnit(_ wallet: WalletBalance) -> String {
        // This sentinel is created by TypeSafe when the service has not supplied a currency.
        !wallet.isMonetary && wallet.currency == "credits（币种未提供）" ? L10n.text("credits（币种未提供）") : wallet.currency
    }

    static func count(_ value: Decimal, window: QuotaWindow) -> String {
        quantity(value, formatted: count(value), window: window)
    }

    private static func quantity(_ value: Decimal, formatted: String, window: QuotaWindow) -> String {
        if let unit = QuotaLabelPresentation.quantityUnit(window) {
            if let integer = Int64(exactly: NSDecimalNumber(decimal: value).doubleValue), Decimal(integer) == value {
                return L10n.format(unit.integerKey, integer)
            }
            // Preserve all Decimal digits without a hidden/dummy native plural selector.
            return L10n.format(value == 1 ? unit.singularKey : unit.pluralKey, formatted)
        }
        return withUnit(formatted, unit: L10n.windowUnit(window))
    }

    static func count(_ value: Double?, window: QuotaWindow) -> String {
        guard let value else { return L10n.text("未提供") }
        if value.isFinite, QuotaLabelPresentation.quantityUnit(window) != nil {
            return quantity(Decimal(value), formatted: count(value), window: window)
        }
        return withUnit(count(value, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2), unit: L10n.windowUnit(window))
    }

    static func providerPlanName(_ raw: String?, presentation: QuotaPlanPresentation? = nil,
                                 language: String? = nil) -> String? {
        guard let presentation else { return raw }
        switch presentation {
        case .payAsYouGo: return L10n.text("按量计费", language: language)
        case .team(let identifier): return L10n.format("团队 %@", identifier, language: language)
        }
    }

    static func withUnit(_ value: String, unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return value }
        return L10n.format("%@ %@", value, unit)
    }

    static func quotaStatus(_ raw: String?, provider: Provider, language: String? = nil) -> String? {
        guard let raw else { return nil }
        return QuotaLabelPresentation.status(raw, provider: provider, language: language)
    }

    /// Wallet status wording shared by the account card, Watch pages and widgets.
    /// The badge form is the short inline label; the detail form is the full sentence.
    static var walletUnavailableBadge: String { L10n.text("余额不足") }
    static var walletUnavailableDetail: String { L10n.text("余额不足，无法调用 API") }
    static var quotaExceededBadge: String { L10n.text("额度已用尽") }

    static func limitDescription(_ window: QuotaWindow) -> String? {
        window.isUnlimited ? L10n.text("无限") : nil
    }

    static func refreshFailure(_ failure: RefreshFailure, hasSnapshot: Bool) -> String {
        L10n.format(hasSnapshot ? "刷新失败：%@。已保留上次成功数据。" : "刷新失败：%@。", failure.displayName)
    }
}

/// Native catalog lookup for strings that are returned by shared presentation code.
/// Language is device-local; numeric and date formatting still use the effective region.
enum L10n {
    @TaskLocal static var languageOverride: String?

    static func withLanguage<Result>(_ language: String, operation: () throws -> Result) rethrows -> Result {
        try $languageOverride.withValue(language, operation: operation)
    }

    static func withLanguage<Result>(_ language: String, isolation: isolated (any Actor)? = #isolation,
                                     operation: () async throws -> Result) async rethrows -> Result {
        try await $languageOverride.withValue(language, operation: operation, isolation: isolation)
    }

    static func text(_ key: String, language: String? = nil) -> String {
        let localization = (language ?? languageOverride).map { $0.hasPrefix("zh-Hans") || $0.hasPrefix("zh-CN") ? "zh-Hans" : "en" }
        let bundle = localization.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg..., language: String? = nil, locale: Locale = .autoupdatingCurrent) -> String {
        let effectiveLanguage = language ?? languageOverride ?? Bundle.main.preferredLocalizations.first ?? "en"
        let isChinese = effectiveLanguage.hasPrefix("zh-Hans") || effectiveLanguage.hasPrefix("zh-CN")
        // Native plural rules follow the format locale's language. Keep the user's
        // region, explicit locale options and actual numbering system, but select
        // grammar using the same supported language as the catalog lookup.
        var components = Locale.Components(locale: locale)
        components.languageComponents.languageCode = Locale.LanguageCode(isChinese ? "zh" : "en")
        components.languageComponents.script = isChinese ? Locale.Script("Hans") : nil
        components.numberingSystem = locale.numberingSystem
        return String(format: text(key, language: language), locale: Locale(components: components), arguments: arguments)
    }

    static func windowName(_ window: QuotaWindow, provider: Provider? = nil, language: String? = nil) -> String {
        QuotaLabelPresentation.name(window, provider: provider, language: language)
    }

    static func windowDisplayName(_ window: QuotaWindow, provider: Provider? = nil, language: String? = nil) -> String {
        let name = windowName(window, provider: provider, language: language)
        return windowScope(window, language: language).map { format("%@ %@", $0, name, language: language) } ?? name
    }

    static func windowScope(_ window: QuotaWindow, language: String? = nil) -> String? {
        QuotaLabelPresentation.scope(window, language: language)
    }

    static func windowUnit(_ window: QuotaWindow, language: String? = nil) -> String? {
        QuotaLabelPresentation.unit(window, language: language)
    }

    static func demoAccountName(_ account: SubscriptionAccount, language: String? = nil) -> String {
        guard DemoIdentity.isSample(account.id), account.name.hasPrefix("演示 · ") else { return account.name }
        let name = String(account.name.dropFirst(5))
        let sample = QuotaLabelPresentation.demoNames.contains(name) ? text(name, language: language) : name
        return format("演示 · %@", sample, language: language)
    }
}

private enum DemoIdentity {
    static func isSample(_ id: UUID) -> Bool { id.uuidString.hasPrefix("DE000000-0000-0000-0000-") }
}

/// Compatibility presentation for existing caches. IDs and provider scope prove ownership;
/// only known app labels are looked up, and original names, units and archives stay untouched.
private enum QuotaLabelPresentation {
    static let labelsByFamily: [String: Set<String>] = [
        "copilot": ["Premium requests", "Chat", "Completions"],
        "claude": ["5 小时额度", "每周额度"],
        "codex": ["额度窗口", "5 小时额度", "每周额度", "每月额度"],
        "opencode-go": ["5 小时额度", "每周额度", "每月额度"],
        "zai": ["额度窗口", "5 小时额度", "每周额度", "每月额度"],
        "superGrok": ["额度窗口", "5 小时额度", "每周额度", "每月额度", "SuperGrok 套餐额度"],
        "minimax": ["5 小时额度", "每周额度", "每月额度"],
        "qwenCloud": ["5 小时额度", "每周额度", "每月额度"],
        "kimiCode": ["5 小时额度", "每周额度", "每月总额度", "加量余额"],
        "miniMax": ["5 小时额度", "每周额度", "每月额度"],
        "zhipu": ["5 小时额度", "每周额度", "每月额度"],
        "qoder": ["个人额度", "组织资源包"],
        "stepfun": ["Token Plan 积分额度", "5 小时额度", "每周额度", "每月额度"],
        "jetbrains": ["订阅额度", "额外额度", "AI 额度"],
        "elevenlabs": ["账期字符额度"],
        "poe": ["剩余 points"],
        "vercelAIGateway": ["API 钱包余额"],
        "newAPI": ["无限 Key", "API 钱包余额", "Token 余额", "余额单位未知"],
        "moonshot": ["API 钱包余额"],
        "codebuff": ["credits 额度", "剩余 credits"],
        "neuralwatt": ["订阅能量额度", "Key 支出限额", "API 钱包余额"],
        "clawRouter": ["每月预算"],
        "aixy": ["每月预算", "每日预算", "每周预算", "累计预算", "每月监控预算", "每日监控预算", "每周监控预算", "累计监控预算"],
        "factory": ["5 小时额度", "每周额度", "每月额度", "附加用量余额"],
        "kiloCode": ["API 钱包余额", "Kilo Pass 当期额度"],
        "deepInfra": ["API 钱包余额", "支出上限"],
        "commandCode": ["5 小时消费限额", "每日消费限额", "每周消费限额", "每月消费限额", "累计消费限额", "组织消费限额", "可用美元余额"],
        "amp": ["Amp Free · 逐小时补充", "Amp Free · 每日额度", "Agent 账期额度", "Orb 账期额度", "个人美元余额"],
        "gitKraken": ["个人 AI 额度", "组织共享 AI 额度"],
        "huggingFace": ["GPU 时长额度"],
        "synthetic": ["5 小时滚动额度", "每周滚动额度", "每小时额度"],
        "v2ex": ["5 小时额度", "5 小时额度（尚未开始）", "额外用量补充包"],
        "xkiro": ["额度窗口", "5 小时额度", "每周额度", "每月额度", "每日免费 tokens", "API 钱包余额"],
        "zenmux": ["5 小时额度", "每周额度", "每月额度", "按量钱包余额"],
        "alibabaCodingPlan": ["5 小时额度", "每周额度", "账期额度"],
        "alibabaTokenPlan": ["5 小时额度", "每周额度", "每月额度"],
        "chutes": ["4 小时固定额度", "账期额度"],
        "cursor": ["每月额度", "套餐金额额度", "额外支出额度"],
        "volcengine": ["5 小时额度", "每周额度", "每月额度"],
        "ibmBob": ["Bobcoins（预算未提供）"],
        "devpass": ["Premium 每周额度", "账期 credits", "Key 累计限额"],
        "v0": ["账期 credits", "消息限流"],
        "devin": ["每日额度", "每周额度", "超额使用余额"],
        "windsurf": ["每日额度", "每周额度"],
        "nous": ["订阅 credits", "购买 credits", "总可用 credits"],
        "manus": ["恢复额度", "每日恢复额度", "每月额度", "总 credits"],
        "longcat": ["当前 Token 包", "账户 Token 额度", "补充燃料包总额", "即将到期燃料包（补充包子集）"],
        "qoderChina": ["个人额度（含资源包）", "团队额度", "个人额度", "组织资源包", "即将到期资源包（个人额度子集）"],
        "ollama": ["会话额度", "每小时额度", "每周额度"],
        "abacus": ["Compute points 额度"],
        "perplexity": ["API credits 余额"],
        "augmentCode": ["本账期 credits"],
        "zed": ["编辑预测", "AI 支出预算"],
        "grokBot": ["Grok Bot 每周额度"],
        "raycast": ["AI credits"],
        "t3chat": ["4 小时额度", "每月额度"],
        "zoommate": ["credits 预算"],
        "clinePass": ["5 小时额度", "每周额度", "每月额度"],
        "liteLLM": ["团队预算", "用户预算", "团队预算（上限未提供）", "用户预算（上限未提供）"],
        "llmProxy": ["配额组"],
        "sakana": ["5 小时额度", "每周额度", "已标币种余额", "服务 credits 余额（币种未提供）"],
        "mistral": ["账期额度", "可用钱包余额"],
        "replicate": ["预付美元余额"],
        "xaiAPI": ["已入账预付余额"],
        "warp": ["套餐 credits"],
        "sub2api": ["API 钱包余额", "分组配额", "每日预算", "每周预算", "每月预算"],
    ]
    static let statusesByProvider: [String: Set<String>] = [
        "kiro": ["服务未提供可显示的额度池"],
        "jetBrainsAI": ["服务未提供可显示的额度池"],
        "antigravity": ["未返回模型组额度"],
        "nousPortal": ["当前未开放付费服务"],
        "bifrost": ["虚拟 Key 已停用", "未配置可读取预算"],
        "llmProxy": ["代理未提供可读取的配额组"],
        "liteLLM": ["未提供可计算的预算上限或用量", "未提供可计算的团队预算上限或用量", "此 Key 无权读取预算信息", "Key 未绑定可读取的用户或团队预算", "此 Key 无权读取用户或团队预算"],
        "qwenCloud": ["当前账号没有 Qwen Cloud 套餐"],
        "alibabaTokenPlan": ["未提供个人 Token Plan 额度"],
        "notionAI": ["所选工作区没有适用的 Notion AI 额度"],
        "augmentCode": ["总额度口径未确认，仅显示报告计数"],
        "qoderChina": ["当前没有已授予的个人或团队 credits"],
        "xiaomiCodingPlan": ["没有当前 Coding Plan；余额与套餐额度分开显示"],
        "grokBot": ["Grok Bot 使用组织共享额度，未返回个人份额", "此账号未包含 Grok Bot 个人额度"],
        "longCat": ["当前 Token 包未提供消耗量", "账户 Token 用量未提供", "主 Token 额度未授予；补充包本次未取得", "当前没有已授予的 Token 包或燃料包", "补充燃料包本次未取得", "当前 Token 包未提供消耗量；补充燃料包本次未取得", "账户 Token 用量未提供；补充燃料包本次未取得"],
        "zed": ["未返回支出预算上限，仅显示已花金额", "已设置零支出预算"],
        "devin": ["当前组织未分配套餐额度", "套餐额度由服务隐藏", "每日额度由服务隐藏", "每周额度由服务隐藏"],
        "zoomMate": ["服务当前不允许使用这项额度"],
    ]
    static let demoNames: Set<String> = [
        "MiniMax 国内版",
        "Qoder 国际版",
        "DeepSeek 钱包",
        "Kimi Code 国内版",
        "Vercel AI Gateway 钱包",
        "智谱国内版",
        "MiniMax 国际版",
        "New API 钱包",
        "sub2api 分组",
        "Bifrost 虚拟 Key",
        "LiteLLM 用户与团队",
        "LLM Proxy 配额组",
        "Moonshot 国内 API 钱包",
        "Moonshot 国际 API 钱包",
        "百炼 Coding Plan",
        "Chutes 订阅预算",
        "Cursor 模型池",
        "火山方舟",
        "xAI API 团队余额",
        "IBM Bob 团队预算",
        "小米月度套餐与余额",
        "Qoder 国内个人与团队",
        "LongCat Token 与燃料包",
        "OpenAI API Legacy 余额",
        "百炼 Personal Token Plan",
        "Antigravity 模型组"
    ]
    static let demoAliases: [String: String] = [
        "5-hour allowance": "5 小时额度",
        "Weekly allowance": "每周额度",
        "Service credits (currency not provided)": "服务 credits 余额（币种未提供）",
        "Billing allowance": "账期额度",
        "Available balance": "可用钱包余额",
        "Prepaid USD balance": "预付美元余额",
        "Personal AI credits": "个人 AI 额度",
        "Organization AI credits": "组织共享 AI 额度",
        "GPU time quota": "GPU 时长额度",
    ]

    static func name(_ window: QuotaWindow, provider: Provider?, language: String?) -> String {
        if let label = window.presentationLabel {
            switch label {
            case .monthlyTokenAllowance: return L10n.text("月度 Token 额度", language: language)
            case .extraAllowance: return L10n.text("额外额度", language: language)
            case .geminiModelGroup: return L10n.text("Gemini 模型组", language: language)
            case .providerModel: return window.name
            case .modelDisabled:
                let suffix = "（未启用）"
                guard window.name.hasSuffix(suffix) else { return window.name }
                return L10n.format("%@（未启用）", String(window.name.dropLast(suffix.count)), language: language)
            }
        }
        let family = window.id.components(separatedBy: ".").first ?? ""
        if window.id.hasPrefix("demo.") { return L10n.text(window.name, language: language) }
        if provider == .miniMaxChina || provider == .miniMaxInternational {
            if window.id.hasSuffix(".interval"), window.name == "短周期额度" { return L10n.text(window.name, language: language) }
            if window.id.hasSuffix(".interval"), let n = hours(window.name, suffix: " 小时额度") {
                return L10n.format("%lld 小时额度", n, language: language)
            }
            if window.id.hasSuffix(".weekly"), window.name == "每周额度" { return L10n.text(window.name, language: language) }
        }
        let raw = demoAliases[window.name] ?? window.name
        if labelsByFamily[family]?.contains(raw) == true { return L10n.text(raw, language: language) }
        // Codex IDs include the original feature name followed by a stable slot and period.
        let parts = window.id.components(separatedBy: ".")
        let periodIDs = ["claude", "zai", "superGrok", "xkiro"]
        let isCodex = parts.count >= 3 && ["primary_window", "secondary_window"].contains(parts[parts.count - 2])
        if isCodex || periodIDs.contains(family) {
            if ["额度窗口", "5 小时额度", "每周额度", "每月额度"].contains(raw) { return L10n.text(raw, language: language) }
            if let value = hours(raw, suffix: " 小时额度") { return L10n.format("%lld 小时额度", value, language: language) }
        }
        if family == "deepseek", let wallet = window.wallet,
           raw == "\(wallet.currency) 钱包" { return L10n.format("%@ 钱包", wallet.currency, language: language) }
        if family == "deepseek", raw == "API 钱包余额" { return L10n.text(raw, language: language) }
        let walletFamilies = ["openAIAPI", "typesafe", "typeSafe", "atlasCloud", "hyper", "venice", "kiloCode", "deepInfra", "xiaomi", "qoderChina"]
        if walletFamilies.contains(family), let wallet = window.wallet {
            if raw == "API 钱包余额" { return L10n.text(raw, language: language) }
            if raw == "剩余 \(wallet.currency)" {
                let unit = window.id == "typesafe.balance" ? L10n.text("credits（币种未提供）", language: language) : wallet.currency
                return L10n.format("剩余 %@", unit, language: language)
            }
        }
        if family == "sub2api", let wallet = window.wallet, raw == "可用 \(wallet.currency)" {
            return L10n.format("可用 %@", wallet.currency, language: language)
        }
        if family == "bifrost", raw.hasSuffix(" USD 预算") {
            let duration = String(raw.dropLast(" USD 预算".count))
            return L10n.format("%@ USD 预算", duration == "无周期" ? L10n.text("无周期", language: language) : duration, language: language)
        }
        if family == "sub2api", window.id.hasPrefix("sub2api.rate."), raw.hasSuffix(" 限流额度") {
            return L10n.format("%@ 限流额度", String(raw.dropLast(" 限流额度".count)), language: language)
        }
        if family == "aixy", raw.hasSuffix("（用量未提供）") {
            let name = String(raw.dropLast("（用量未提供）".count))
            if labelsByFamily[family]?.contains(name) == true {
                return L10n.format("%@（用量未提供）", L10n.text(name, language: language), language: language)
            }
        }
        if family == "kiro" {
            // Monthly/trial/overage names always append app-owned annotations to a provider label.
            let suffixes = [(".monthly", "（订阅额度）", "%@（订阅额度）"),
                            (".trial", "（试用）", "%@（试用）"),
                            (".trial", "（试用，到期时间未提供）", "%@（试用，到期时间未提供）"),
                            (".unidentified", "（多笔同刻到期，单池标识未提供）", "%@（多笔同刻到期，单池标识未提供）")]
            for (idSuffix, suffix, key) in suffixes where window.id.hasSuffix(idSuffix) && raw.hasSuffix(suffix) {
                return L10n.format(key, String(raw.dropLast(suffix.count)), language: language)
            }
            if window.id.contains(".credit."), raw.hasSuffix("（额外 credits）") {
                return L10n.format("%@（额外 credits）", String(raw.dropLast("（额外 credits）".count)), language: language)
            }
            // Bonus display names come from the service and stay verbatim.
        }
        // Legacy Antigravity names cannot prove whether a disabled-looking suffix
        // was app-added or actually part of a provider model name. Keep them raw.
        if family == "notionAI", window.id.hasSuffix(".billing") || window.id.hasSuffix(".rolling") {
            let split = raw.range(of: " · ", options: .backwards)
            let label = split.map { String(raw[$0.upperBound...]) } ?? raw
            let translated: String?
            if ["账期 AI 额度", "滚动 AI 额度"].contains(label) { translated = L10n.text(label, language: language) }
            else if let n = hours(label, suffix: " 小时 AI 额度") { translated = L10n.format("%lld 小时 AI 额度", n, language: language) }
            else { translated = nil }
            if let translated { return split.map { L10n.format("%@ · %@", String(raw[..<$0.lowerBound]), translated, language: language) } ?? translated }
        }
        if family == "warp", window.id.hasPrefix("warp.grant."),
           let range = raw.range(of: " 附加 credits ", options: .backwards), let n = Int64(raw[range.upperBound...]) {
            let scope = String(raw[..<range.lowerBound])
            let translated: String
            if scope == "个人" { translated = L10n.text("个人", language: language) }
            else if scope.hasPrefix("工作区 "), let index = Int64(scope.dropFirst("工作区 ".count)) {
                translated = L10n.format("工作区 %lld", index, language: language)
            } else { translated = scope }
            return L10n.format("%@ 附加 credits %lld", translated, n, language: language)
        }
        if family == "chutes", window.id == "chutes.rolling", raw.hasPrefix("滚动额度（"), raw.hasSuffix("）") {
            let duration = String(raw.dropFirst("滚动额度（".count).dropLast())
            for (suffix, key) in [(" 小时", "%lld 小时"), (" 分钟", "%lld 分钟"), (" 秒", "%lld 秒")] {
                if let n = hours(duration, suffix: suffix) {
                    return L10n.format("滚动额度（%@）", L10n.format(key, n, language: language), language: language)
                }
            }
        }
        return window.name
    }

    private static func hours(_ raw: String, suffix: String) -> Int64? {
        guard raw.hasSuffix(suffix) else { return nil }
        let count = String(raw.dropLast(suffix.count))
        guard !count.isEmpty, count.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int64(count), n > 0 else { return nil }
        return n
    }

    enum QuantityUnit {
        case request, shortRequest, message, gpuSecond, character, hour, unknownUnit, allowanceUnit, credit

        var integerKey: String {
            switch self {
            case .request: "%lld 次请求"
            case .shortRequest: "%lld 次（请求计数）"
            case .message: "%lld 条消息"
            case .gpuSecond: "%lld GPU 秒"
            case .character: "%lld 字符"
            case .hour: "%lld 小时"
            case .unknownUnit: "%lld 单位（类型未提供）"
            case .allowanceUnit: "%lld 额度单位"
            case .credit: "%lld credits"
            }
        }
        var singularKey: String {
            switch self {
            case .request: "%@ 次请求（单数）"
            case .shortRequest: "%@ 次（请求单数）"
            case .message: "%@ 条消息（单数）"
            case .gpuSecond: "%@ GPU 秒（单数）"
            case .character: "%@ 字符（单数）"
            case .hour: "%@ 小时（单数）"
            case .unknownUnit: "%@ 单位（类型未提供，单数）"
            case .allowanceUnit: "%@ 额度单位（单数）"
            case .credit: "%@ credits（单数）"
            }
        }
        var pluralKey: String {
            switch self {
            case .request: "%@ 次请求（复数）"
            case .shortRequest: "%@ 次（请求复数）"
            case .message: "%@ 条消息（复数）"
            case .gpuSecond: "%@ GPU 秒（复数）"
            case .character: "%@ 字符（复数）"
            case .hour: "%@ 小时（复数）"
            case .unknownUnit: "%@ 单位（类型未提供，复数）"
            case .allowanceUnit: "%@ 额度单位（复数）"
            case .credit: "%@ credits（复数）"
            }
        }
    }

    static func quantityUnit(_ window: QuotaWindow) -> QuantityUnit? {
        if window.presentationUnit == .unspecifiedQuotaUnit { return .allowanceUnit }
        if window.presentationUnit == .unspecifiedUnitType ||
            (window.id.hasPrefix("antigravity.bucket.") && window.unit == "单位（类型未提供）") { return .unknownUnit }
        let family = window.id.components(separatedBy: ".").first ?? ""
        if ["copilot", "alibabaCodingPlan", "zed", "synthetic"].contains(family),
           ["次", "次请求"].contains(window.unit ?? "") { return window.unit == "次" ? .shortRequest : .request }
        if window.id == "v0.rate_limit", window.unit == "条消息" { return .message }
        if window.id == "huggingFace.zeroGPU", window.unit == "GPU 秒" { return .gpuSecond }
        if window.id == "elevenlabs.characters", window.unit == "字符" { return .character }
        if window.id == "amp.orb", window.unit == "小时" { return .hour }
        // These fixed Manus pools measure app-owned quota counts. Wallet/vendor
        // currency codes and unknown namespaces are intentionally not inflected.
        if ["manus.refresh", "manus.monthly"].contains(window.id), window.wallet == nil,
           window.unit == "credits" { return .credit }
        return nil
    }

    static func unit(_ window: QuotaWindow, language: String?) -> String? {
        if let presentation = window.presentationUnit {
            return L10n.text(presentation == .unspecifiedQuotaUnit ? "额度单位" : "单位（类型未提供）", language: language)
        }
        guard let raw = window.unit else { return nil }
        let family = window.id.components(separatedBy: ".").first ?? ""
        let ownsRequests = ["copilot", "alibabaCodingPlan", "zed", "synthetic", "v0"]
        if ownsRequests.contains(family), ["次", "次请求"].contains(raw) { return L10n.text(raw == "次" ? "请求次数单位" : "次请求", language: language) }
        if window.id == "elevenlabs.characters", raw == "字符" { return L10n.text(raw, language: language) }
        if window.id == "amp.orb", raw == "小时" { return L10n.text(raw, language: language) }
        // Antigravity always generated this amount sentinel itself; it never came from a server unit field.
        if window.id.hasPrefix("antigravity.bucket."), raw == "单位（类型未提供）" { return L10n.text(raw, language: language) }
        if window.id == "stepfun.credits", raw == "积分" { return L10n.text("积分", language: language) }
        if ["liteLLM", "bifrost", "xkiro"].contains(family), raw == "USD 预算额度" { return L10n.text(raw, language: language) }
        if ["cursor", "chutes", "zed"].contains(family), raw == "USD 预算" { return L10n.text(raw, language: language) }
        if window.id == "factory.extraUsage", raw == "cents（币种未提供）" { return L10n.text(raw, language: language) }
        if window.id == "v0.rate_limit", raw == "条消息" { return L10n.text("条消息", language: language) }
        if window.id == "huggingFace.zeroGPU", raw == "GPU 秒" { return L10n.text(raw, language: language) }
        if window.id == "typesafe.balance", raw == "credits（币种未提供）" { return L10n.text(raw, language: language) }
        return raw
    }

    static func scope(_ window: QuotaWindow, language: String?) -> String? {
        if let presentation = window.presentationScope {
            let kind: String? = presentation.kind.map { kind in
                let key: String = switch kind {
                case .organization: "组织"
                case .project: "项目"
                case .team: "团队"
                case .user: "用户"
                case .apiKey: "Key"
                }
                return kind == .apiKey ? key : L10n.text(key, language: language)
            }
            let name = presentation.name.flatMap { $0.isEmpty ? nil : $0 }
            let scope: String? = switch (kind, name) {
            case (.some(let kind), .some(let name)): L10n.format("%@ · %@", kind, name, language: language)
            case (.some(let kind), .none): kind
            case (.none, .some(let name)): name
            case (.none, .none): Optional<String>.none
            }
            if presentation.isShared {
                return scope.map { L10n.format("%@ · 共享", $0, language: language) } ?? L10n.text("共享", language: language)
            }
            return scope
        }
        guard let raw = window.scope else { return nil }
        if window.id.hasPrefix("liteLLM.") {
            for prefix in ["团队 · ", "用户 · "] where raw.hasPrefix(prefix) {
                return L10n.format(prefix == "团队 · " ? "团队 · %@" : "用户 · %@", String(raw.dropFirst(prefix.count)), language: language)
            }
        }
        if window.id.hasPrefix("sub2api."), ["限流", "分组订阅"].contains(raw) { return L10n.text(raw, language: language) }
        if window.id.hasPrefix("bifrost.") {
            if raw == "虚拟 Key" { return L10n.text(raw, language: language) }
            for prefix in ["提供商 · ", "模型 · ", "虚拟 Key · "] where raw.hasPrefix(prefix) {
                return L10n.format(prefix == "模型 · " ? "模型 · %@" : prefix == "虚拟 Key · " ? "虚拟 Key · %@" : "Provider · %@", String(raw.dropFirst(prefix.count)), language: language)
            }
        }
        if window.id == "gitKraken.organization" {
            if raw == "默认组织（接口未提供名称）" { return L10n.text(raw, language: language) }
            if raw.hasPrefix("组织 ") { return L10n.format("组织 %@", String(raw.dropFirst("组织 ".count)), language: language) }
        }
        return raw
    }

    static func status(_ raw: String, provider: Provider, language: String?) -> String {
        statusesByProvider[provider.rawValue]?.contains(raw) == true ? L10n.text(raw, language: language) : raw
    }
}
