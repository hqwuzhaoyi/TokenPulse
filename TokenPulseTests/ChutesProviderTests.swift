import Foundation
import XCTest
@testable import TokenPulse

final class ChutesProviderTests: XCTestCase {
    private let body = #"{"subscription":true,"monthly_price":10,"four_hour":{"usage":"1.234567890123456789","cap":"4.166666666666666667","remaining":"2.932098776543209878","reset_at":"2026-11-01T04:00:00+00:00"},"monthly":{"usage":25,"cap":50,"remaining":25,"reset_at":"2026-11-15T00:00:00+00:00"}}"#

    func testPrimaryRequestAndExactUSDBudgetAreNotWalletOrRequestCount() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        let transport = ChutesTestTransport([(200, body)])
        let credential = try ProviderAuthenticationController().credential(provider: .chutes, apiKey: " fixture-key ")
        let snapshot = try await ProviderQuotaClient(provider: .chutes, transport: transport, now: { now })
            .quota(for: UUID(), credential: credential)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.chutes.ai/users/me/subscription_usage")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(snapshot.collectedAt, now)
        XCTAssertEqual(snapshot.windows.map(\.period), [.other, .monthly])
        XCTAssertEqual(snapshot.windows[0].name, "4 小时固定额度")
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "1.234567890123456789"))
        XCTAssertEqual(snapshot.windows[0].exactCounts?.remaining, Decimal(string: "2.932098776543209878"))
        XCTAssertEqual(snapshot.windows[0].exactCounts?.total, Decimal(string: "4.166666666666666667"))
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.unit == "USD 预算" && $0.wallet == nil })
        XCTAssertEqual(snapshot.windows[1].usedPercentage, 50)
        XCTAssertNil(snapshot.walletAvailable)
        XCTAssertFalse(Provider.chutes.hasMonetaryWallet)
    }

    func testCustomUncappedMonthlyIsUnlimitedWithoutInventedPercentageOrReset() throws {
        let data = Data(#"{"subscription":true,"custom":true,"four_hour":{"usage":10,"cap":10,"remaining":0},"monthly":{"uncapped":true}}"#.utf8)
        let snapshot = try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].isExhausted, true)
        let monthly = snapshot.windows[1]
        XCTAssertTrue(monthly.isUnlimited)
        XCTAssertNil(monthly.usedPercentage)
        XCTAssertNil(monthly.exactCounts)
        XCTAssertNil(monthly.resetsAt)
        XCTAssertEqual(QuotaFormatting.usage(monthly), "无限")
        XCTAssertNil(WidgetQuotaMetric(id: monthly.id, title: monthly.name, window: monthly).ringFraction)
    }

    func testNoSubscriptionMissingLimitAndExhaustionHaveDifferentStates() throws {
        for body in [#"{"subscription":false}"#, #"{"subscription":false,"four_hour":{"usage":1,"cap":10}}"#] {
            XCTAssertThrowsError(try ChutesProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .subscriptionRequired)
            }
        }
        let missing = try ChutesProviderClient.snapshot(Data(#"{"subscription":true,"four_hour":{"usage":1}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertNil(missing.windows[0].usedPercentage)
        XCTAssertNil(missing.windows[0].totalCount)
        XCTAssertEqual(missing.windows[0].exactCounts?.used, 1)
        XCTAssertNil(missing.windows[0].exactCounts?.total)
        XCTAssertNil(missing.windows[0].exactCounts?.remaining)
        XCTAssertTrue(QuotaFormatting.usage(missing.windows[0]).hasPrefix("已用 1"))
        XCTAssertNil(missing.windows[0].isExhausted)
        let spent = try ChutesProviderClient.snapshot(Data(#"{"subscription":true,"four_hour":{"usage":11,"cap":10}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(spent.windows[0].isExhausted, true)
        XCTAssertEqual(spent.windows[0].exactCounts?.used, 11)
        XCTAssertEqual(spent.windows[0].exactCounts?.remaining, 0)
        XCTAssertEqual(spent.windows[0].usedPercentage, 110)
        XCTAssertThrowsError(try ChutesProviderClient.snapshot(Data(#"{"subscription":true,"four_hour":{"usage":0,"cap":0}}"#.utf8), accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
    }

    func testPartialBudgetFieldsKeepKnownDecimalAmountsAcrossSerialization() throws {
        let text = "1.234567890123456789"
        let cases: [(String, Decimal?, Decimal?, Decimal?)] = [
            ("usage", Decimal(string: text), nil, nil),
            ("remaining", nil, Decimal(string: text), nil),
            ("cap", nil, nil, Decimal(string: text)),
        ]
        for (field, used, remaining, total) in cases {
            let data = Data("{\"subscription\":true,\"four_hour\":{\"\(field)\":\"\(text)\"}}".utf8)
            let snapshot = try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
            let counts = try XCTUnwrap(snapshot.windows.first?.exactCounts)
            XCTAssertEqual(counts.used, used)
            XCTAssertEqual(counts.remaining, remaining)
            XCTAssertEqual(counts.total, total)
            XCTAssertNil(snapshot.windows.first?.usedPercentage)
            XCTAssertNil(snapshot.windows.first?.isExhausted)
            XCTAssertNotEqual(QuotaFormatting.usage(snapshot.windows[0]), "未提供")
            let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot))
            XCTAssertEqual(restored.windows.first?.exactCounts, counts)
        }
    }

    func testInexactDerivedUsageCannotErasePositiveRemainingOrClaimExhaustion() throws {
        let data = Data(#"{"subscription":true,"four_hour":{"cap":"100000000000000000","remaining":"0.0000000000000000000001"}}"#.utf8)
        let snapshot = try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertNil(window.exactCounts?.used)
        XCTAssertEqual(window.exactCounts?.total, Decimal(string: "100000000000000000"))
        XCTAssertEqual(window.exactCounts?.remaining, Decimal(string: "0.0000000000000000000001"))
        XCTAssertNil(window.isExhausted)
        XCTAssertNil(window.usedPercentage)
    }

    func testNearFullExactBudgetDoesNotTriggerHundredPercentFromRoundedDisplay() throws {
        let date = Date(timeIntervalSince1970: 100), id = UUID()
        let data = Data(#"{"subscription":true,"four_hour":{"usage":"99999999999999999","cap":"100000000000000000","remaining":1}}"#.utf8)
        let snapshot = try ChutesProviderClient.snapshot(data, accountID: id, collectedAt: date)
        XCTAssertEqual(snapshot.windows.first?.isExhausted, false)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Chutes", previousSnapshot: nil,
                                                               newSnapshot: snapshot, settings: AccountReminderSettings(thresholds: [100]),
                                                               ledger: ReminderLedger(), now: date)
        XCTAssertTrue(result.operations.isEmpty)
    }

    func testUnknownFieldsBooleanNumbersAndUnitsAreNeverGuessed() {
        for body in [
            #"{"subscription":1,"four_hour":{"usage":1,"cap":10}}"#,
            #"{"subscription":true,"four_hour":{"usage":true,"cap":10}}"#,
            #"{"subscription":true,"monthly":{"uncapped":1}}"#,
            #"{"subscription":true,"four_hour":{"usage":"NaN","cap":10}}"#,
            #"{"subscription":true,"four_hour":{"usage":-1,"cap":10}}"#,
            #"{"subscription":true,"some_unrelated":{"usage":1,"cap":10}}"#,
            #"{"subscription":true,"rolling_window":{"usage":1,"cap":10}}"#
        ] { XCTAssertThrowsError(try ChutesProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) }
    }

    func testFixedFixtureCompatibilityPreservesExplicitUnitsAndScaleWithoutDefaultDuration() throws {
        let body = #"{"subscription":{"active":true,"plan_name":"Pro"},"monthly":{"percent_used":0.5,"unit":"credits"},"rolling_window":{"requests":40,"limit":100,"window_minutes":240,"reset_at":"2026-11-01T04:00:00Z","unit":"requests"}}"#
        let snapshot = try ChutesProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 40)
        XCTAssertEqual(snapshot.windows[0].unit, "requests")
        XCTAssertEqual(snapshot.windows[1].usedPercentage, 0.5, "0.5 is a stated percent, never multiplied by 100")
        XCTAssertEqual(snapshot.windows[1].unit, "credits")
        let missingDuration = body.replacingOccurrences(of: #""window_minutes":240,"#, with: "")
        let shorter = try ChutesProviderClient.snapshot(Data(missingDuration.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(shorter.windows.map(\.id), ["chutes.monthly"])
        let invalidDuration = body.replacingOccurrences(of: "240", with: "true")
        let rejected = try ChutesProviderClient.snapshot(Data(invalidDuration.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(rejected.windows.map(\.id), ["chutes.monthly"])
    }

    func testLegacyPositiveTinyRemainingCannotRoundIntoExhaustionOrHundredPercentAlert() throws {
        let date = Date(timeIntervalSince1970: 1000)
        for (total, remaining) in [("100000000000000000", "0.00000000000000000000001"), ("1000", "0.0000000000001")] {
            for quoted in [false, true] {
                let limitJSON = quoted ? "\"\(total)\"" : total
                let remainingJSON = quoted ? "\"\(remaining)\"" : remaining
                let data = Data("{\"subscription\":{\"active\":true},\"rolling_window\":{\"limit\":\(limitJSON),\"remaining\":\(remainingJSON),\"window_seconds\":3600,\"unit\":\"credits\"}}".utf8)
                let id = UUID()
                let snapshot = try ChutesProviderClient.snapshot(data, accountID: id, collectedAt: date)
                let window = try XCTUnwrap(snapshot.windows.first)
                XCTAssertEqual(window.exactCounts?.remaining, Decimal(string: remaining))
                XCTAssertEqual(window.exactCounts?.total, Decimal(string: total))
                XCTAssertNotEqual(window.isExhausted, true)
                XCTAssertFalse(window.usedPercentage.map { $0 >= 100 } ?? false)
                if total == "100000000000000000" {
                    XCTAssertNil(window.exactCounts?.used, "An unrepresentable difference must remain unknown")
                    XCTAssertNil(window.usedPercentage)
                    XCTAssertNil(window.isExhausted)
                } else {
                    XCTAssertEqual(window.exactCounts?.used, Decimal(string: "999.9999999999999"))
                    XCTAssertEqual(window.isExhausted, false)
                }
                let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Chutes legacy",
                    previousSnapshot: nil, newSnapshot: snapshot,
                    settings: AccountReminderSettings(resetRemindersEnabled: false, thresholds: [100]),
                    ledger: ReminderLedger(), now: date)
                XCTAssertTrue(result.operations.isEmpty)
            }
        }
    }

    func testLegacyTypedDecimalPartialCountsAndWrappersPreserveKnownAmounts() throws {
        let amount = "1.234567890123456789"
        for field in ["used", "requests", "remaining", "limit"] {
            for wrapper in ["data", "result"] {
                let data = Data("{\"\(wrapper)\":{\"subscription\":{\"active\":true},\"monthly\":{\"\(field)\":\"\(amount)\",\"unit\":\"credits\"}}}".utf8)
                let snapshot = try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
                let counts = try XCTUnwrap(snapshot.windows.first?.exactCounts)
                XCTAssertEqual(counts.used, field == "used" || field == "requests" ? Decimal(string: amount) : nil)
                XCTAssertEqual(counts.remaining, field == "remaining" ? Decimal(string: amount) : nil)
                XCTAssertEqual(counts.total, field == "limit" ? Decimal(string: amount) : nil)
                XCTAssertNil(snapshot.windows[0].usedPercentage)
                XCTAssertNil(snapshot.windows[0].isExhausted)
                XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
            }
        }
    }

    func testLegacyPercentOnlyWithOptionalLimitKeepsDeclaredScale() throws {
        for limit in ["", ",\"limit\":100"] {
            let data = Data("{\"subscription\":{\"active\":true},\"monthly\":{\"percent_used\":0.5\(limit),\"unit\":\"credits\"}}".utf8)
            let snapshot = try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
            XCTAssertEqual(snapshot.windows[0].usedPercentage, 0.5)
            XCTAssertEqual(snapshot.windows[0].isExhausted, false)
            XCTAssertNil(snapshot.windows[0].exactCounts?.used)
            XCTAssertNil(snapshot.windows[0].exactCounts?.remaining)
        }
    }

    func testLegacyInactiveSubscriptionAndUnknownPeriodRetainTheirFailureSemantics() throws {
        for field in ["\"active\":false", "\"status\":\"expired\"", "\"status\":\"free\""] {
            let data = Data("{\"subscription\":{\(field)},\"monthly\":{\"limit\":100,\"remaining\":99}}".utf8)
            XCTAssertThrowsError(try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .subscriptionRequired)
            }
        }
        let unknown = Data(#"{"subscription":{"active":true},"rolling_window":{"limit":100,"remaining":99}}"#.utf8)
        XCTAssertThrowsError(try ChutesProviderClient.snapshot(unknown, accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
    }

    func testKnownDataAndResultWrapsKeepDecimalAndDoNotInventNumericResetUnits() throws {
        for key in ["data", "result"] {
            let data = Data("{\"\(key)\":\(body)}".utf8)
            let snapshot = try ChutesProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
            XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "1.234567890123456789"))
        }
        let missing = try ChutesProviderClient.snapshot(Data(#"{"subscription":true,"four_hour":{"usage":1,"cap":10,"reset_at":1800000000000}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertNil(missing.windows[0].resetsAt)
    }

    func testHTTPFailuresCancellationAndWrongProviderFailWithoutFallback() async throws {
        let encoded = try ProviderAuthenticationController().credential(provider: .chutes, apiKey: "fixture")
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            let transport = ChutesTestTransport([(status, "{}"), (200, body)])
            do { _ = try await ProviderQuotaClient(provider: .chutes, transport: transport).quota(for: UUID(), credential: encoded); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        let transport = ChutesTestTransport([], cancelled: true)
        do { _ = try await ProviderQuotaClient(provider: .chutes, transport: transport).quota(for: UUID(), credential: encoded); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        let unused = ChutesTestTransport([])
        let wrong = try ProviderAuthenticationController().credential(provider: .poe, apiKey: "fixture")
        do { _ = try await ProviderQuotaClient(provider: .chutes, transport: unused).quota(for: UUID(), credential: wrong); XCTFail() }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
        let requests = await unused.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testWidgetCodingAndNotificationsPreserveBudgetAndNeverSendWalletAlerts() throws {
        let account = SubscriptionAccount(name: "fixture", provider: .chutes)
        let now = Date(timeIntervalSince1970: 1000)
        let data = Data(#"{"subscription":true,"four_hour":{"usage":9.5,"cap":10,"remaining":0.5,"reset_at":"2026-11-01T04:00:00Z"},"monthly":{"uncapped":true}}"#.utf8)
        let snapshot = try ChutesProviderClient.snapshot(data, accountID: account.id, collectedAt: now)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertTrue(widget.displayMetrics[0].valueText.contains("USD 预算"))
        XCTAssertEqual(widget.displayMetrics[1].valueText, "无限")
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let planner = NotificationPlanner()
        let result = planner.planSuccessfulRefresh(accountID: account.id, accountName: account.name, previousSnapshot: nil, newSnapshot: snapshot,
            settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        let delivered = result.operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(delivered.map(\.kind), [.quotaAlert])
        XCTAssertFalse(delivered[0].body.contains("账期"))
        XCTAssertTrue(result.operations.contains { if case .schedule = $0 { return true }; return false })
        let repeated = planner.planSuccessfulRefresh(accountID: account.id, accountName: account.name, previousSnapshot: snapshot, newSnapshot: snapshot,
            settings: AccountReminderSettings(), ledger: result.ledger, now: now)
        XCTAssertTrue(repeated.operations.isEmpty)
    }

    @MainActor
    func testMultipleAccountsRestartFailureDeletionAndSeparateWatchMonitorRefresh() async throws {
        let phoneSuite = "chutes.phone.tests.\(UUID().uuidString)"
        let watchSuite = "chutes.watch.tests.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: phoneSuite)?.removePersistentDomain(forName: phoneSuite)
            UserDefaults(suiteName: watchSuite)?.removePersistentDomain(forName: watchSuite)
        }
        let credentials = ChutesTestCredentials()
        let transport = ChutesTestTransport([(200, body), (200, body), (401, "{}")])
        let client = ProviderQuotaClient(provider: .chutes, transport: transport)
        let store = LocalAccountStateStore(suiteName: phoneSuite)
        let configurations = LocalAccountConfigurationStore(suiteName: phoneSuite)
        let phone = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: configurations)
        await phone.start(refresh: false)
        let auth = ProviderAuthenticationController()
        let aKey = try auth.credential(provider: .chutes, apiKey: "a-fixture")
        let bKey = try auth.credential(provider: .chutes, apiKey: "b-fixture")
        await phone.addAccount(name: "A", credential: aKey, provider: .chutes)
        await phone.addAccount(name: "B", credential: bKey, provider: .chutes)
        let a = try XCTUnwrap(phone.states.first), b = try XCTUnwrap(phone.states.last)
        await phone.refresh(accountID: a.id)
        XCTAssertEqual(phone.states[0].snapshot, a.snapshot)
        XCTAssertEqual(phone.states[0].lastFailure, .invalidCredential)
        XCTAssertEqual(phone.states[1], b)
        let restored = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: configurations)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, phone.states)
        let now = Date(timeIntervalSince1970: 555)
        let watchTransport = ChutesTestTransport([(200, body), (200, body)])
        let watch = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: watchSuite), credentialStore: credentials,
            quotaClient: ProviderQuotaClient(provider: .chutes, transport: watchTransport, now: { now }),
            configurationStore: LocalAccountConfigurationStore(suiteName: watchSuite))
        await watch.start(refresh: false)
        await watch.mergeSynchronized(configurations: restored.configurations, states: restored.states)
        await watch.refreshAll()
        XCTAssertTrue(watch.states.allSatisfy { $0.snapshot?.collectedAt == now && $0.lastFailure == nil })
        let requests = await watchTransport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer a-fixture", "Bearer b-fixture"])
        let didDelete = await restored.deleteAccount(accountID: a.id)
        XCTAssertTrue(didDelete)
        let deleted = await credentials.credential(for: a.id)
        let kept = await credentials.credential(for: b.id)
        XCTAssertNil(deleted)
        XCTAssertEqual(kept, bKey)
    }
}

private actor ChutesTestTransport: ProviderTransport {
    private var replies: [(Int, String)]
    private let cancelled: Bool
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)], cancelled: Bool = false) { self.replies = replies; self.cancelled = cancelled }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        if cancelled { throw CancellationError() }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor ChutesTestCredentials: CredentialStoring {
    private var items: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { items[accountID] = credential }
    func credential(for accountID: UUID) -> String? { items[accountID] }
    func deleteCredential(for accountID: UUID) { items[accountID] = nil }
}
