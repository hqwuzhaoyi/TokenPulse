import Foundation
import XCTest
@testable import TokenPulse

/// Wallet presentation tests shared by the iPhone widget, the Watch widget and the Watch app pages.
final class WalletPresentationTests: XCTestCase {
    private func walletWindow(_ currency: String, total: Decimal) -> QuotaWindow {
        QuotaWindow(
            id: "deepseek.wallet.\(currency)", name: "\(currency) 钱包", scope: nil,
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
            unit: currency,
            wallet: WalletBalance(currency: currency, total: total, granted: 1, toppedUp: total - 1)
        )
    }

    func testSelectedWalletCurrencyComesFromConfigurationAndReachesTheWidgetSnapshot() async throws {
        let suite = "com.tokenpulse.tests.wallet-presentation.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "wallet-presentation")
        let account = SubscriptionAccount(name: "DeepSeek 钱包", provider: .deepSeek)
        let state = AccountQuotaState(account: account, snapshot: QuotaSnapshot(
            accountID: account.id,
            windows: [walletWindow("CNY", total: 110), walletWindow("USD", total: 8)],
            collectedAt: Date(timeIntervalSince1970: 500)
        ))

        // No configuration yet: the first returned currency is the display fallback.
        try await store.save(states: [state])
        let fallbackSnapshots = await store.load()
        let fallback = try XCTUnwrap(fallbackSnapshots.first)
        XCTAssertNil(fallback.walletCurrency)
        XCTAssertEqual(fallback.displayMetrics.map { $0.window?.wallet?.currency }, ["CNY"])

        // Selecting USD in the account settings must republish the same account with USD.
        var configuration = AccountConfiguration(account: account)
        configuration.reminders.walletCurrency = "USD"
        try await store.save(states: [state], configurations: [configuration])
        let selectedSnapshots = await store.load()
        let selected = try XCTUnwrap(selectedSnapshots.first)
        XCTAssertEqual(selected.walletCurrency, "USD")
        XCTAssertEqual(selected.displayMetrics.map { $0.window?.wallet?.currency }, ["USD"])
        XCTAssertEqual(selected.displayMetrics.first?.valueText, "8 USD")
        XCTAssertEqual(selected.collectedAt, Date(timeIntervalSince1970: 500))
    }

    func testMissingSelectedCurrencyShowsNotProvidedWithoutAutoSwitching() async throws {
        let account = SubscriptionAccount(name: "DeepSeek 钱包", provider: .deepSeek)
        let snapshot = WidgetAccountSnapshot(
            account: account,
            windows: [walletWindow("CNY", total: 110)],
            collectedAt: Date(),
            lastFailure: nil,
            walletCurrency: "USD"
        )
        let metric = try XCTUnwrap(snapshot.displayMetrics.first)
        XCTAssertEqual(metric.title, "USD")
        XCTAssertNil(metric.window)
        XCTAssertEqual(metric.valueText, L10n.text("未提供"))
        XCTAssertNil(metric.ringFraction)
    }

    func testEmptyBalanceArrayKeepsUnavailableStatusWithoutFabricatingZero() {
        let account = SubscriptionAccount(name: "DeepSeek 钱包", provider: .deepSeek)
        for available in [true, false] {
            let snapshot = WidgetAccountSnapshot(
                account: account, windows: [], collectedAt: Date(), lastFailure: nil,
                walletCurrency: "CNY", walletAvailable: available
            )
            // The selected currency is still shown as "未提供" rather than dropped or zeroed.
            XCTAssertEqual(snapshot.displayMetrics.map(\.valueText), [L10n.text("未提供")])
            XCTAssertNil(snapshot.displayMetrics.first?.window)
            XCTAssertNil(snapshot.displayMetrics.first?.ringFraction)
            XCTAssertEqual(snapshot.walletAvailable, available)
        }
    }

    func testWalletMetricsNeverExposeUsagePercentageOrResetTimeline() {
        let zero = WalletBalance(currency: "USD", total: 0, granted: 0, toppedUp: 0)
        let window = QuotaWindow(
            id: "deepseek.wallet.USD", name: "USD 钱包", scope: nil,
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: zero
        )
        let metric = WidgetQuotaMetric(id: "wallet.USD", title: "USD", window: window)
        XCTAssertEqual(metric.valueText, "0 USD")
        XCTAssertNil(metric.ringFraction)
        XCTAssertNil(window.usedPercentage)
        XCTAssertNil(window.resetsAt)
        XCTAssertEqual(QuotaFormatting.money(zero.total, currency: "USD"), "0 USD")
    }

    func testWalletRefreshFailureKeepsPreviousBalanceAndCollectedAtOnlyForThatAccount() async throws {
        let suite = "com.tokenpulse.tests.wallet-failure.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "wallet-failure")
        let failing = SubscriptionAccount(name: "钱包 A", provider: .deepSeek)
        let healthy = SubscriptionAccount(name: "钱包 B", provider: .deepSeek)
        let oldDate = Date(timeIntervalSince1970: 100)
        let states = [
            AccountQuotaState(
                account: failing,
                snapshot: QuotaSnapshot(accountID: failing.id, windows: [walletWindow("CNY", total: 50)],
                                        collectedAt: oldDate),
                lastFailure: .network
            ),
            AccountQuotaState(
                account: healthy,
                snapshot: QuotaSnapshot(accountID: healthy.id, windows: [walletWindow("CNY", total: 20)],
                                        collectedAt: Date(timeIntervalSince1970: 200)),
                lastFailure: nil
            ),
        ]
        try await store.save(states: states)
        let loaded = await store.load()
        let failingSnapshot = try XCTUnwrap(loaded.first { $0.id == failing.id })
        XCTAssertEqual(failingSnapshot.lastFailure, .network)
        XCTAssertEqual(failingSnapshot.collectedAt, oldDate)
        XCTAssertEqual(failingSnapshot.displayMetrics.first?.valueText, "50 CNY")
        let healthySnapshot = try XCTUnwrap(loaded.first { $0.id == healthy.id })
        XCTAssertNil(healthySnapshot.lastFailure)
        XCTAssertEqual(healthySnapshot.displayMetrics.first?.valueText, "20 CNY")
    }

    func testQoderWidgetShowsPersonalAndOrganizationWithoutGlobalOption() {
        let account = SubscriptionAccount(name: "Qoder", provider: .qoderInternational)
        let personal = QuotaWindow(id: "qoder.userQuota", name: "个人额度", scope: nil,
                                   usedPercentage: 25, remainingCount: 750, totalCount: 1_000, resetsAt: nil)
        let organization = QuotaWindow(id: "qoder.orgResourcePackage", name: "组织资源包", scope: nil,
                                       usedPercentage: 50, remainingCount: 100, totalCount: 200, resetsAt: nil)
        let snapshot = WidgetAccountSnapshot(account: account, windows: [personal, organization],
                                             collectedAt: Date(), lastFailure: nil)

        XCTAssertEqual(snapshot.displayMetrics.map { $0.window?.id },
                       ["qoder.userQuota", "qoder.orgResourcePackage"])
    }

    func testQoderOrganizationProviderPercentageDrivesWidgetProgressWhenOnlyRemainingIsKnown() throws {
        let root = try ProviderHTTP.json(Data("""
        {
          "orgResourcePackage": {"remaining": 3000, "percentage": 0.25, "unit": "credits"}
        }
        """.utf8))
        let organization = try XCTUnwrap(QoderProviderClient.windows(root).first)
        let account = SubscriptionAccount(name: "Qoder", provider: .qoderInternational)
        let snapshot = WidgetAccountSnapshot(
            account: account, windows: [organization], collectedAt: Date(), lastFailure: nil
        )
        let metric = try XCTUnwrap(snapshot.displayMetrics.first)

        XCTAssertEqual(organization.remainingCount, 3000)
        XCTAssertEqual(organization.usedPercentage, 25)
        XCTAssertEqual(metric.valueText, "3,000 credits")
        XCTAssertEqual(metric.ringFraction, 0.25)
    }
}

// These tests use a task-local language to leave parallel tests and device preferences intact.
import Testing

struct QuotaLocalizationPresentationTests {
    private func window(_ id: String, _ name: String, unit: String? = nil,
                        counts: DecimalQuotaCounts? = nil) -> QuotaWindow {
        QuotaWindow(id: id, name: name, scope: nil, usedPercentage: 50,
                    remainingCount: nil, totalCount: nil, resetsAt: nil, unit: unit, exactCounts: counts)
    }

    @Test func cachedAppLabelsResolveWithoutChangingWindowOrAccountIdentity() throws {
        let account = SubscriptionAccount(name: "我自己的 每周额度", provider: .liteLLM)
        let budget = QuotaWindow(id: "liteLLM.team.existing", name: "团队预算", scope: "团队 · 原始 team",
            period: .monthly, usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil,
            unit: "USD 预算额度", exactCounts: .init(used: 20, remaining: 80, total: 100))
        let stored = WidgetAccountSnapshot(account: account, windows: [budget], collectedAt: Date(timeIntervalSince1970: 100), lastFailure: .network)
        let data = try JSONEncoder().encode(stored)
        let cached = try JSONDecoder().decode(WidgetAccountSnapshot.self, from: data)
        let original = try JSONEncoder().encode(cached)
        L10n.withLanguage("en") {
            #expect(L10n.windowName(budget) == "Team budget")
            #expect(L10n.windowDisplayName(budget) == "Team · 原始 team Team budget")
            #expect(L10n.windowUnit(budget) == "USD budget allowance")
            #expect(cached.displayMetrics.first?.title == "Team · 原始 team Team budget")
            #expect(cached.displayMetrics.first?.valueText == "80 / 100 USD budget allowance")
            #expect(L10n.demoAccountName(cached.account) == account.name)
        }
        L10n.withLanguage("zh-Hans") {
            #expect(L10n.windowName(budget) == "团队预算")
            #expect(cached.displayMetrics.first?.title == "团队 · 原始 team 团队预算")
        }
        #expect(cached.account == account)
        #expect(cached.windows == stored.windows)
        #expect(cached.id == account.id)
        #expect(cached.collectedAt == stored.collectedAt)
        #expect(cached.lastFailure == stored.lastFailure)
        #expect(try JSONDecoder().decode(WidgetAccountSnapshot.self, from: original) == cached)
    }

    @Test func providerGeneratedLabelsUseTrustedIdentityAndPreserveUnknownText() {
        let unknown = window("thirdParty.pool", "每周额度")
        let model = window("gemini.每周额度", "每周额度", unit: "额度单位")
        let rawBonus = window("kiro.CREDIT.bonus.existing", "额外额度")
        L10n.withLanguage("en") {
            #expect(L10n.windowName(unknown) == "每周额度")
            #expect(L10n.windowName(model) == "每周额度")
            #expect(L10n.windowUnit(model) == "额度单位")
            #expect(L10n.windowName(rawBonus) == "额外额度")
            #expect(L10n.windowName(window("factory.extraUsage", "服务原文")) == "服务原文")
            #expect(L10n.windowName(window("kiro.CREDIT.monthly", "服务积分（订阅额度）")) == "服务积分 (subscription allowance)")
            #expect(L10n.windowName(window("notionAI.workspace.billing", "我自己的工作区 · 账期 AI 额度")) == "我自己的工作区 · Billing AI allowance")
            #expect(L10n.windowName(window("feature.primary_window.fiveHour", "5 小时额度")) == L10n.text("5 小时额度"))
            #expect(L10n.windowName(window("customPool.interval", "短周期额度")) == "短周期额度")
            #expect(L10n.windowName(window("customPool.interval", "短周期额度"), provider: .miniMaxChina) == "Short-period allowance")
            #expect(L10n.windowName(window("customPool.interval", "8 小时额度"), provider: .miniMaxInternational) == "8-hour allowance")
        }
    }

    @Test func nativePluralCountsDistinguishZeroOneAndMany() {
        L10n.withLanguage("en") {
            #expect(QuotaFormatting.remainingResets(0) == "0 resets")
            #expect(QuotaFormatting.remainingResets(1) == "1 reset")
            #expect(QuotaFormatting.remainingResets(3) == "3 resets")
            #expect(QuotaFormatting.remainingResets(nil) == "Not provided")
            let requests = window("copilot.chat", "Chat", unit: "次")
            #expect(QuotaFormatting.count(Decimal(0), window: requests) == "0 requests")
            #expect(QuotaFormatting.count(Decimal(1), window: requests) == "1 request")
            #expect(QuotaFormatting.count(Decimal(3), window: requests) == "3 requests")
            let messages = window("v0.rate_limit", "消息限流", unit: "条消息")
            #expect(QuotaFormatting.count(Decimal(1), window: messages) == "1 message")
            #expect(QuotaFormatting.count(Decimal(2), window: messages) == "2 messages")
            let amount: Double = 123.456
            #expect(QuotaFormatting.count(amount, window: messages) == "123.46 messages")
        }
        L10n.withLanguage("zh-Hans") {
            #expect(QuotaFormatting.remainingResets(0) == "0 次")
            #expect(QuotaFormatting.remainingResets(1) == "1 次")
            #expect(QuotaFormatting.remainingResets(3) == "3 次")
        }
    }

    @Test func nativePluralGrammarUsesTranslationLanguageAndRetainsRegionalNumbers() {
        for identifier in ["zh_CN", "en_US", "de_DE", "en_DE@numbers=arab", "ar_EG", "en_IN", "de_CH"] {
            let locale = Locale(identifier: identifier)
            for count in [0, 1, 3, 1234, 1_234_567] {
                let number = String(format: "%lld", locale: locale, arguments: [Int64(count)])
                #expect(QuotaFormatting.remainingResets(count, language: "en", locale: locale) == "\(number) \(count == 1 ? "reset" : "resets")")
                #expect(QuotaFormatting.remainingResets(count, language: "zh-Hans", locale: locale) == "\(number) 次")
                #expect(QuotaFormatting.remainingResets(count, language: "fr", locale: locale) == "\(number) \(count == 1 ? "reset" : "resets")")
                L10n.withLanguage("en") {
                    #expect(L10n.format("%lld 次请求", Int64(count), locale: locale) == "\(number) \(count == 1 ? "request" : "requests")")
                    #expect(L10n.format("%lld 条消息", Int64(count), locale: locale) == "\(number) \(count == 1 ? "message" : "messages")")
                    #expect(L10n.format("%lld GPU 秒", Int64(count), locale: locale) == "\(number) GPU \(count == 1 ? "second" : "seconds")")
                }
            }
        }
    }

    @Test func walletBudgetCreditsAndGPUUnitsKeepSeparateMeanings() {
        L10n.withLanguage("en") {
            let points = WalletBalance(currency: "points", total: Decimal(string: "123.45678901")!, isMonetary: false)
            #expect(QuotaFormatting.balance(points.total, wallet: points, locale: Locale(identifier: "en_US")) == "123.45678901 points")
            #expect(QuotaFormatting.balance(nil, wallet: points) == "Not provided")
            #expect(QuotaFormatting.balance(0, wallet: points) == "0 points")
            let unknownCurrency = WalletBalance(currency: "credits（币种未提供）", total: 4.98, isMonetary: false)
            #expect(QuotaFormatting.balance(unknownCurrency.total, wallet: unknownCurrency, locale: Locale(identifier: "en_US")) == "4.98 credits (currency not provided)")
            #expect(unknownCurrency.currency == "credits（币种未提供）")
            #expect(!unknownCurrency.isMonetary)
            let gpu = window("huggingFace.zeroGPU", "GPU 时长额度", unit: "GPU 秒", counts: .init(remaining: 1))
            #expect(QuotaFormatting.exactCountSummary(gpu) == "Remaining 1 GPU second")
            #expect(gpu.unit == "GPU 秒")
            #expect(gpu.wallet == nil)
            let monetary = WalletBalance(currency: "EUR", total: Decimal(string: "1234.56789012")!)
            #expect(QuotaFormatting.balance(monetary.total, wallet: monetary, locale: Locale(identifier: "de_DE")) == "1.234,56789012 EUR")
            #expect(QuotaFormatting.balance(monetary.total, wallet: monetary, locale: Locale(identifier: "en_US")) == "1,234.56789012 EUR")
        }
    }

    @Test func quotaStateAndFailuresAreLocalizedWithoutReplacingUnknownWithZero() {
        var missing = window("zed.editPredictions", "编辑预测")
        missing = QuotaWindow(id: missing.id, name: missing.name, scope: nil, usedPercentage: nil,
            remainingCount: nil, totalCount: nil, resetsAt: nil)
        let unlimited = QuotaWindow(id: "copilot.chat", name: "Chat", scope: nil, isUnlimited: true,
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil)
        L10n.withLanguage("en") {
            #expect(QuotaFormatting.usage(missing) == "Not provided")
            #expect(QuotaFormatting.usage(unlimited) == "Unlimited")
            #expect(QuotaFormatting.effectiveUsedPercentage(unlimited) == nil)
            #expect(QuotaFormatting.quotaStatus("未配置可读取预算", provider: .bifrost) == "No readable budget is configured")
            #expect(QuotaFormatting.quotaStatus("未配置可读取预算", provider: .gemini) == "未配置可读取预算")
            #expect(QuotaFormatting.quotaStatus("服务原始状态", provider: .bifrost) == "服务原始状态")
            #expect(QuotaFormatting.walletUnavailableBadge == "Insufficient balance")
            #expect(QuotaFormatting.walletCollectionStatus(failure: .network, collectedAt: nil)?.hasPrefix("Wallet refresh failed:") == true)
            #expect(QuotaFormatting.refreshFailure(.network, hasSnapshot: true).hasSuffix("Previous successful data was kept."))
        }
        L10n.withLanguage("zh-Hans") {
            #expect(QuotaFormatting.usage(missing) == "未提供")
            #expect(QuotaFormatting.usage(unlimited) == "无限")
            #expect(QuotaFormatting.walletUnavailableBadge == "余额不足")
        }
    }

    @Test func optionalFallbackProvenancePreservesLegacyAndProviderText() throws {
        let legacy = window("xiaomi.plan.0", "月度 Token 额度", unit: "tokens", counts: .init(used: 2, remaining: 8, total: 10))
        let marked = QuotaWindow(id: legacy.id, name: legacy.name, scope: legacy.scope,
            usedPercentage: legacy.usedPercentage, remainingCount: legacy.remainingCount,
            totalCount: legacy.totalCount, resetsAt: legacy.resetsAt, unit: legacy.unit,
            exactCounts: legacy.exactCounts, presentationLabel: .monthlyTokenAllowance)
        let restored = try JSONDecoder().decode(QuotaWindow.self, from: JSONEncoder().encode(marked))
        let old = try JSONDecoder().decode(QuotaWindow.self, from: JSONEncoder().encode(legacy))
        #expect(old.presentationLabel == nil)
        #expect(restored.presentationLabel == .monthlyTokenAllowance)
        #expect(restored.id == legacy.id)
        #expect(restored.name == legacy.name)
        #expect(restored.unit == legacy.unit)
        #expect(restored.exactCounts == legacy.exactCounts)
        L10n.withLanguage("en") {
            #expect(L10n.windowName(old) == "月度 Token 额度")
            #expect(L10n.windowName(restored) == "Monthly Token allowance")
            let providerUnit = window("gemini.model", "Model", unit: "额度单位")
            #expect(L10n.windowUnit(providerUnit) == "额度单位")
            let fallbackUnit = QuotaWindow(id: providerUnit.id, name: providerUnit.name, scope: nil,
                usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                unit: "额度单位", presentationUnit: .unspecifiedQuotaUnit)
            #expect(L10n.windowUnit(fallbackUnit) == "Allowance units")
            #expect(fallbackUnit.unit == "额度单位")
        }
    }

    @Test func providerFallbackProducersMarkOnlyMissingSourceText() throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 1000)
        let usage = Data(#"{"code":0,"data":{"monthUsage":{"items":[{"used":2,"limit":10},{"name":"月度 Token 额度","used":2,"limit":10}]}}}"#.utf8)
        let xiaomi = try XiaomiCodingPlanProviderClient.snapshot(usage: usage, detail: nil, balance: nil, accountID: id, collectedAt: now)
        #expect(xiaomi.windows.map(\.name) == ["月度 Token 额度", "月度 Token 额度"])
        #expect(xiaomi.windows[0].presentationLabel == .monthlyTokenAllowance)
        #expect(xiaomi.windows[1].presentationLabel == nil)
        let kiro = try KiroProviderParser.snapshot([
            "usageBreakdownList": .array([.map([
                "resourceType": .string("CREDIT"), "displayNamePlural": .string("credits"), "unit": .string("credits"),
                "bonuses": .array([
                    .map(["status": .string("ACTIVE"), "bonusCode": .string("missing"), "currentUsage": .integer(1), "usageLimit": .integer(10)]),
                    .map(["status": .string("ACTIVE"), "bonusCode": .string("reported"), "displayName": .string("额外额度"), "currentUsage": .integer(1), "usageLimit": .integer(10)])
                ])
            ])])
        ], accountID: id, collectedAt: now)
        #expect(kiro.windows.map(\.name) == ["额外额度", "额外额度"])
        #expect(kiro.windows[0].presentationLabel == .extraAllowance)
        #expect(kiro.windows[1].presentationLabel == nil)
        let gemini = try GeminiProviderClient.snapshot(Data(#"{"buckets":[{"modelId":"a","remainingFraction":0.5},{"modelId":"b","remainingFraction":0.5,"tokenType":"额度单位"}]}"#.utf8), accountID: id, collectedAt: now)
        #expect(gemini.windows[0].presentationUnit == .unspecifiedQuotaUnit)
        #expect(gemini.windows[1].presentationUnit == nil)
        L10n.withLanguage("en") {
            #expect(L10n.windowName(xiaomi.windows[0]) == "Monthly Token allowance")
            #expect(L10n.windowName(xiaomi.windows[1]) == "月度 Token 额度")
            #expect(L10n.windowName(kiro.windows[0]) == "Extra allowance")
            #expect(L10n.windowName(kiro.windows[1]) == "额外额度")
            #expect(L10n.windowUnit(gemini.windows[0]) == "Allowance units")
            #expect(L10n.windowUnit(gemini.windows[1]) == "额度单位")
            #expect(L10n.windowName(gemini.windows[0]) == "a")
        }
        let sample = try #require(DemoMode.accounts().first { $0.provider == .xiaomiCodingPlan })
        let demo = DemoMode.snapshot(accountID: sample.id, provider: sample.provider)
        let monthly = try #require(demo.windows.first { $0.id == "xiaomi.plan.0" })
        #expect(monthly.name == "月度 Token 额度")
        #expect(monthly.presentationLabel == .monthlyTokenAllowance)
        L10n.withLanguage("en") { #expect(L10n.windowName(monthly) == "Monthly Token allowance") }
        #expect(xiaomi.accountID == id)
        #expect(kiro.accountID == id)
        #expect(gemini.accountID == id)
    }

    @Test func taskLocalLanguageRestoresAfterNestedOverride() {
        L10n.withLanguage("en") {
            #expect(QuotaFormatting.remainingResets(nil) == "Not provided")
            L10n.withLanguage("zh-Hans") { #expect(QuotaFormatting.remainingResets(nil) == "未提供") }
            #expect(QuotaFormatting.remainingResets(nil) == "Not provided")
        }
    }
}

struct QuotaPresentationSupplementTests {
    private func quantityWindow(_ id: String, unit: String, remaining: Decimal? = nil) -> QuotaWindow {
        QuotaWindow(id: id, name: "原始 label", scope: nil, usedPercentage: nil, remainingCount: nil,
                    totalCount: nil, resetsAt: nil, unit: unit, exactCounts: remaining.map { .init(remaining: $0) })
    }

    @Test func physicalUnitsPluralizeWithoutChangingValuesOrUnknownUnits() throws {
        let characters = quantityWindow("elevenlabs.characters", unit: "字符")
        let hours = quantityWindow("amp.orb", unit: "小时")
        L10n.withLanguage("en") {
            for (value, word) in [(0, "characters"), (1, "character"), (3, "characters")] {
                #expect(QuotaFormatting.count(Decimal(value), window: characters) == "\(value) \(word)")
            }
            for (value, word) in [(0, "hours"), (1, "hour"), (3, "hours")] {
                #expect(QuotaFormatting.count(Decimal(value), window: hours) == "\(value) \(word)")
            }
            let exact = Decimal(string: "1.000000000000000001")!
            #expect(QuotaFormatting.count(exact, window: hours) == "\(QuotaFormatting.count(exact)) hours")
            let approximate: Double = 123.456
            #expect(QuotaFormatting.count(approximate, window: characters) == "123.46 characters")
            #expect(L10n.windowUnit(quantityWindow("thirdParty.units", unit: "字符")) == "字符")
            #expect(L10n.windowUnit(quantityWindow("gemini.model", unit: "小时")) == "小时")
        }
        L10n.withLanguage("zh-Hans") {
            #expect(QuotaFormatting.count(Decimal(1), window: characters) == "1 字符")
            #expect(QuotaFormatting.count(Decimal(3), window: hours) == "3 小时")
        }
        #expect(characters.unit == "字符")
        #expect(hours.unit == "小时")
        #expect(hours.wallet == nil)
    }

    @Test func realCharacterHourAndRecoveryProducersKeepTheirOriginalUnitsAndIDs() throws {
        let characters = try #require(ElevenLabsProviderClient.windows(Data(#"{"character_count":1,"character_limit":3}"#.utf8)).first)
        let text = "Amp Megawatt Tier: agent usage $18.57 of $20 remaining (93%), orb usage 1h of 3h a1.small orb hours remaining (33%) - period 2026-09-13 to 2026-10-13, resets upon renewal in 27 days"
        let ampData = try JSONSerialization.data(withJSONObject: ["ok": true, "result": ["displayText": text]])
        let orb = try #require(AmpProviderClient.snapshot(ampData, accountID: UUID(), collectedAt: Date()).windows.first { $0.id == "amp.orb" })
        let manus = try #require(ManusProviderClient.snapshot(Data(#"{"refreshCredits":1,"maxRefreshCredits":3,"refreshInterval":"weekly"}"#.utf8), accountID: UUID(), collectedAt: Date()).windows.first)
        L10n.withLanguage("en") {
            #expect(QuotaFormatting.usage(characters) == "2 / 3 characters")
            #expect(QuotaFormatting.usage(orb) == "1 / 3 hours")
            #expect(L10n.windowName(manus) == "Replenishing allowance")
        }
        #expect(characters.id == "elevenlabs.characters")
        #expect(characters.unit == "字符")
        #expect(orb.unit == "小时")
        #expect(orb.exactCounts?.remaining == 1)
        #expect(orb.exactCounts?.total == 3)
        #expect(orb.wallet == nil)
        #expect(manus.name == "恢复额度")
        #expect(manus.period == .other)
        #expect(manus.wallet == nil)
        for remaining in [0, 1, 2] {
            let input = try JSONSerialization.data(withJSONObject: ["refreshCredits": remaining, "maxRefreshCredits": 3, "refreshInterval": "weekly"])
            let pool = try #require(ManusProviderClient.snapshot(input, accountID: UUID(), collectedAt: Date()).windows.first)
            let exact = try #require(pool.exactCounts?.remaining)
            L10n.withLanguage("en") {
                #expect(QuotaFormatting.count(exact, window: pool) == "\(remaining) \(remaining == 1 ? "credit" : "credits")")
            }
            L10n.withLanguage("zh-Hans") { #expect(QuotaFormatting.count(exact, window: pool) == "\(remaining) credits") }
            #expect(pool.unit == "credits")
            #expect(pool.wallet == nil)
            #expect(pool.exactCounts?.remaining == Decimal(remaining))
        }
        let monthly = try #require(ManusProviderClient.snapshot(Data(#"{"periodicCredits":1,"proMonthlyCredits":3}"#.utf8), accountID: UUID(), collectedAt: Date()).windows.first)
        #expect(monthly.id == "manus.monthly")
        L10n.withLanguage("en") { #expect(QuotaFormatting.count(Decimal(1), window: monthly) == "1 credit") }
        let precisionInput = Data(#"{"refreshCredits":"1.000000000000000001","maxRefreshCredits":"3","refreshInterval":"weekly"}"#.utf8)
        let precise = try #require(ManusProviderClient.snapshot(precisionInput, accountID: UUID(), collectedAt: Date()).windows.first)
        let exact = try #require(precise.exactCounts?.remaining)
        #expect(exact == Decimal(string: "1.000000000000000001"))
        L10n.withLanguage("en") {
            #expect(QuotaFormatting.count(exact, window: precise) == "\(QuotaFormatting.count(exact)) credits")
            let unknown = quantityWindow("thirdParty.credits", unit: "credits")
            #expect(QuotaFormatting.count(Decimal(1), window: unknown) == "1 credits")
            let wallet = WalletBalance(currency: "credits", total: 1, isMonetary: false)
            #expect(QuotaFormatting.balance(wallet.total, wallet: wallet) == "1 credits")
        }
    }

    @Test func modelSuffixOwnershipPreservesRawProviderNamesAndUnknownUnitMeaning() throws {
        let data = Data(#"{"groups":[{"buckets":[{"bucketId":"enabled","displayName":"原始模型（未启用）","remainingFraction":0.5},{"bucketId":"disabled","displayName":"原始模型（未启用）","disabled":true,"remainingFraction":0.5},{"bucketId":"amount","displayName":"原始模型","remainingAmount":"1"}]}]}"#.utf8)
        let snapshot = try AntigravityProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
        let enabled = try #require(snapshot.windows.first { $0.id == "antigravity.bucket.enabled" })
        let disabled = try #require(snapshot.windows.first { $0.id == "antigravity.bucket.disabled" })
        let amount = try #require(snapshot.windows.first { $0.id == "antigravity.bucket.amount" })
        L10n.withLanguage("en") {
            #expect(L10n.windowName(enabled) == "原始模型（未启用）")
            #expect(L10n.windowName(disabled) == "原始模型（未启用） (disabled)")
            #expect(QuotaFormatting.exactCountSummary(amount) == "Remaining 1 unit (type not provided)")
            let legacy = QuotaWindow(id: disabled.id, name: disabled.name, scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil)
            #expect(L10n.windowName(legacy) == disabled.name)
        }
        #expect(enabled.name == "原始模型（未启用）")
        #expect(disabled.name == "原始模型（未启用）（未启用）")
        #expect(amount.unit == "单位（类型未提供）")
        #expect(amount.wallet == nil)
        #expect(amount.exactCounts?.remaining == 1)
        #expect(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test func typedScopeLocalizesOnlyAppComponentsAndLegacyScopeStaysRaw() throws {
        let rawName = "共享 · 团队 用户输入 %@"
        let budget: [String: Any] = ["id": "a", "scope": "team", "target_name": rawName, "shared": true,
            "interval": "monthly", "enforcement": "monitor", "limit_usd": "10",
            "applies_to": [["api_key_id": "key-a", "project_id": "project-a"]],
            "spend_status": "available", "spend_usd": "1"]
        let data = try JSONSerialization.data(withJSONObject: ["object": "key.usage", "currency": "USD",
            "key": ["id": "key-a", "project_id": "project-a"], "budgets": [budget]])
        let actual = try #require(AixyProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date()).windows.first)
        let legacy = QuotaWindow(id: actual.id, name: actual.name, scope: actual.scope,
            usedPercentage: actual.usedPercentage, remainingCount: actual.remainingCount,
            totalCount: actual.totalCount, resetsAt: actual.resetsAt, unit: actual.unit, exactCounts: actual.exactCounts)
        L10n.withLanguage("en") {
            #expect(L10n.windowScope(actual) == "Team · \(rawName) · Shared")
            #expect(L10n.windowScope(legacy) == "团队 · \(rawName) · 共享")
        }
        L10n.withLanguage("zh-Hans") { #expect(L10n.windowScope(actual) == actual.scope) }
        #expect(actual.scope == legacy.scope)
        #expect(actual.presentationScope?.name == rawName)
        #expect(actual.id == legacy.id)
        #expect(actual.exactCounts == legacy.exactCounts)
        #expect(try JSONDecoder().decode(QuotaWindow.self, from: JSONEncoder().encode(actual)) == actual)
    }

    @Test func typedPlanDescriptionsPreserveActualPlansRawTeamIDsAndPaygKeyCaps() throws {
        let devPass = try DevPassProviderClient.snapshot(Data(#"{"data":{"devPlan":"none","usage":"1","limit":"10"}}"#.utf8), accountID: UUID(), collectedAt: Date())
        let teamID = "team-1"
        let xai = try XAIAPIProviderClient.snapshot(Data(#"{"total":{"val":"-1234"}}"#.utf8), accountID: UUID(), teamID: teamID, collectedAt: Date())
        for language in ["zh-Hans", "en"] {
            L10n.withLanguage(language) {
                #expect(QuotaFormatting.providerPlanName(devPass.providerPlanName, presentation: devPass.providerPlanPresentation) == (language == "en" ? "Pay-as-you-go" : "按量计费"))
                #expect(QuotaFormatting.providerPlanName(xai.providerPlanName, presentation: xai.providerPlanPresentation) == (language == "en" ? "Team \(teamID)" : "团队 \(teamID)"))
                #expect(QuotaFormatting.providerPlanName("按量计费") == "按量计费")
                #expect(QuotaFormatting.providerPlanName("团队 用户的套餐原名") == "团队 用户的套餐原名")
            }
        }
        #expect(devPass.providerPlanName == "按量计费")
        #expect(devPass.isNoPlan == nil)
        #expect(devPass.windows.map(\.id) == ["devpass.key_limit"])
        #expect(devPass.windows.first?.exactCounts?.remaining == 9)
        #expect(xai.providerPlanName == "团队 \(teamID)")
        #expect(xai.windows.first?.id == "xaiAPI.team.\(teamID).wallet.USD")
        #expect(xai.windows.first?.wallet?.total == Decimal(string: "12.34"))
        #expect(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(xai)) == xai)
    }

    @Test func oldArchivesDecodeWithoutPresentationAndWidgetCachePreservesNewDescriptors() async throws {
        let suite = "com.tokenpulse.tests.presentation-supplement.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let window = QuotaWindow(id: "aixy.scope", name: "每月预算", scope: "团队 · 原名 · 共享",
            usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil,
            presentationScope: .init(kind: .team, name: "原名", isShared: true))
        let account = SubscriptionAccount(name: "我的原始账号", provider: .aixy)
        var snapshot = QuotaSnapshot(accountID: account.id, windows: [window], collectedAt: Date(timeIntervalSince1970: 100))
        snapshot.providerPlanName = "团队 original-team"
        snapshot.providerPlanPresentation = .team(identifier: "original-team")
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "presentation")
        try await store.save(states: [AccountQuotaState(account: account, snapshot: snapshot)])
        let cached = try #require(await store.load().first)
        #expect(cached.providerPlanName == snapshot.providerPlanName)
        #expect(cached.providerPlanPresentation == snapshot.providerPlanPresentation)
        #expect(cached.windows == snapshot.windows)
        #expect(cached.account == account)
        L10n.withLanguage("en") {
            #expect(L10n.windowScope(cached.windows[0]) == "Team · 原名 · Shared")
            #expect(QuotaFormatting.providerPlanName(cached.providerPlanName, presentation: cached.providerPlanPresentation) == "Team original-team")
        }
        let oldWindow = try JSONDecoder().decode(QuotaWindow.self, from: Data(#"{"id":"old","name":"原名","scope":"团队 · 原名","isUnlimited":false}"#.utf8))
        #expect(oldWindow.presentationScope == nil)
        let encoder = JSONEncoder()
        var oldJSON = try #require(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
        oldJSON.removeValue(forKey: "providerPlanPresentation")
        let oldSnapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        #expect(oldSnapshot.providerPlanPresentation == nil)
        #expect(oldSnapshot.providerPlanName == snapshot.providerPlanName)
    }

    @Test func appOwnedDemoMetadataDoesNotRenameRealProviderModelsOrLegacyScopes() throws {
        let models = try #require(DemoMode.accounts().first { $0.provider == .antigravity })
        let demo = try #require(DemoMode.snapshot(accountID: models.id, provider: models.provider).windows.first)
        let aixy = try #require(DemoMode.accounts().first { $0.provider == .aixy })
        let team = try #require(DemoMode.snapshot(accountID: aixy.id, provider: aixy.provider).windows.first)
        L10n.withLanguage("en") {
            #expect(L10n.windowName(demo) == "Gemini model group")
            #expect(L10n.windowScope(team) == "Team · Shared")
            #expect(L10n.windowName(quantityWindow("antigravity.bucket.service", unit: "tokens")) == "原始 label")
        }
        #expect(demo.name == "Gemini 模型组")
        #expect(team.scope == "团队 · 共享")
    }

    @Test @MainActor func accountScopedWebAuthorizationGuidanceIsLocalizedWithoutHTTP() async throws {
        let transport = SupplementNoNetworkTransport()
        let controller = ProviderAuthenticationController(transport: transport)
        let session = ProviderLoginSession(provider: .replicate, authorizationURL: URL(string: "https://replicate.com")!,
            userCode: nil, deviceCode: nil, state: nil, codeVerifier: nil, callbackURL: nil,
            pollingInterval: nil, expiresAt: nil, metadata: [:])
        for language in ["zh-Hans", "en"] {
            await L10n.withLanguage(language) {
                do {
                    _ = try await controller.continueLogin(session)
                    Issue.record("Web-session providers must use the account-specific flow")
                } catch {
                    guard case ProviderIntegrationError.unsupportedLogin(let guidance) = error else {
                        Issue.record("Expected web flow guidance, got \(error)"); return
                    }
                    #expect(guidance == (language == "en" ? "Use the account-specific web sign-in view" : "请使用该账号专用的网页登录界面"))
                }
            }
        }
        #expect(await transport.requestCount == 0)
    }

    @Test @MainActor func metadataOnlyUpgradePersistsWithoutReschedulingThenRepaintsOfflineAfterRestart() async throws {
        let suite = "com.tokenpulse.tests.presentation-upgrade.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let now = Date(), reset = now.addingTimeInterval(3600), target = "共享 · 原始target"
        let account = SubscriptionAccount(name: "用户原名", provider: .aixy)
        let window = QuotaWindow(id: "aixy.upgrade", name: "每月预算", scope: "团队 · \(target) · 共享",
            period: .monthly, usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: reset,
            presentationScope: .init(kind: .team, name: target, isShared: true))
        let snapshot = QuotaSnapshot(accountID: account.id, windows: [window], collectedAt: now)
        let planner = NotificationPlanner()
        let seed = L10n.withLanguage("zh-Hans") {
            planner.planSuccessfulRefresh(accountID: account.id, accountName: account.name, provider: .aixy,
                previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        }
        // The old app saved the same Chinese text and raw scope, but did not know
        // the new typed scope tag. Keep every event/history field from its JSON.
        let encoder = JSONEncoder()
        var oldJSON = try #require(JSONSerialization.jsonObject(with: encoder.encode(seed.ledger)) as? [String: Any])
        var plans = try #require(oldJSON["pendingResetSchedules"] as? [[String: Any]])
        for index in plans.indices {
            var inputs = try #require(plans[index]["notificationWindows"] as? [[String: Any]])
            for input in inputs.indices { inputs[input].removeValue(forKey: "presentationScope") }
            plans[index]["notificationWindows"] = inputs
        }
        oldJSON["pendingResetSchedules"] = plans
        let oldData = try JSONSerialization.data(withJSONObject: oldJSON)
        let legacyLedger = try JSONDecoder().decode(ReminderLedger.self, from: oldData)
        let before = try #require(legacyLedger.pendingSchedules(accountID: account.id).first)
        defaults.set(oldData, forKey: "reminderLedger")
        let noOps = SupplementNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: noOps)
        try await L10n.withLanguage("zh-Hans") {
            try await runtime.settingsChanged(configurations: [AccountConfiguration(account: account)],
                states: [AccountQuotaState(account: account, snapshot: snapshot)])
        }
        #expect(await noOps.operations.isEmpty)
        let persisted = try #require(defaults.data(forKey: "reminderLedger"))
        var upgraded = try JSONDecoder().decode(ReminderLedger.self, from: persisted)
        let upgradedPlan = try #require(upgraded.pendingSchedules(accountID: account.id).first)
        #expect(upgradedPlan.notification == before.notification)
        #expect(upgradedPlan.notificationID == before.notificationID)
        #expect(upgradedPlan.resetAt == before.resetAt)
        #expect(upgradedPlan.windowIDs == before.windowIDs)
        #expect(upgraded.quotaObservedAt(accountID: account.id) == legacyLedger.quotaObservedAt(accountID: account.id))
        #expect(upgraded.hasExpectedReset(.init(accountID: account.id, windowID: window.id, identity: .expectedAt(reset))))
        // Use the existing newer-observation fence; this test does not grant
        // missing snapshots any new retain eligibility.
        let fence = now.addingTimeInterval(10)
        upgraded.recordQuotaObservation(fence, accountID: account.id)
        defaults.set(try encoder.encode(upgraded), forKey: "reminderLedger")
        let deliveries = SupplementNotificationAdapter()
        let restarted = NotificationRuntime(defaults: defaults, adapter: deliveries)
        try await L10n.withLanguage("en") {
            try await restarted.settingsChanged(configurations: [AccountConfiguration(account: account)], states: [])
        }
        let operations = await deliveries.operations
        #expect(operations.count == 1)
        let operation = try #require(operations.first)
        guard case .schedule(let translated, let date) = operation else { Issue.record("Expected a content-only future replacement"); return }
        #expect(translated.body == "Team · \(target) · Shared Monthly budget")
        #expect(translated.identifier == before.notificationID)
        #expect(date == before.resetAt)
        #expect(restarted.ledger.quotaObservedAt(accountID: account.id) == fence)
        #expect(restarted.ledger.hasExpectedReset(.init(accountID: account.id, windowID: window.id, identity: .expectedAt(reset))))
    }

    @Test @MainActor func futureReminderLanguageChangesPreserveTargetAndSharedScopeFromCache() throws {
        let now = Date(timeIntervalSince1970: 100), reset = now.addingTimeInterval(3600)
        let accountID = UUID(), originalTarget = "共享 · 原名"
        let window = QuotaWindow(id: "aixy.team.fixture", name: "每月预算", scope: "团队 · \(originalTarget) · 共享",
            period: .monthly, usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: reset,
            presentationScope: .init(kind: .team, name: originalTarget, isShared: true))
        let snapshot = QuotaSnapshot(accountID: accountID, windows: [window], collectedAt: now)
        let planner = NotificationPlanner()
        let original = L10n.withLanguage("zh-Hans") {
            planner.planSuccessfulRefresh(accountID: accountID, accountName: "用户原名", provider: .aixy,
                previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        }
        let before = try #require(original.operations.compactMap { operation -> (ReminderNotification, Date)? in
            if case .schedule(let notice, let date) = operation { return (notice, date) }; return nil
        }.first)
        var ledger = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(original.ledger))
        ledger.recordQuotaObservation(now.addingTimeInterval(10), accountID: accountID)
        let changed = L10n.withLanguage("en") {
            planner.planSettingsChange(accountID: accountID, accountName: "用户原名", provider: .aixy,
                latestSnapshot: nil, settings: AccountReminderSettings(), ledger: ledger, now: now.addingTimeInterval(20))
        }
        let after = try #require(changed.operations.compactMap { operation -> (ReminderNotification, Date)? in
            if case .schedule(let notice, let date) = operation { return (notice, date) }; return nil
        }.first)
        #expect(after.0.body == "Team · \(originalTarget) · Shared Monthly budget")
        #expect(after.0.identifier == before.0.identifier)
        #expect(after.1 == before.1)
        #expect(changed.ledger.quotaObservedAt(accountID: accountID) == ledger.quotaObservedAt(accountID: accountID))
        #expect(!changed.operations.contains { if case .deliver = $0 { return true }; return false })
    }
}

private actor SupplementNoNetworkTransport: ProviderTransport {
    var requestCount = 0
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        throw URLError(.notConnectedToInternet)
    }
}

private actor SupplementNotificationAdapter: NotificationApplying {
    var operations: [NotificationOperation] = []
    @MainActor func configure() {}
    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func apply(_ operations: [NotificationOperation]) async throws { self.operations += operations }
}
