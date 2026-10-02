import Foundation
import XCTest
@testable import TokenPulse

final class AmpProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_000)

    private func parse(_ text: String, id: UUID = UUID()) throws -> QuotaSnapshot {
        try AmpProviderClient.snapshot(JSONSerialization.data(withJSONObject: ["ok": true, "result": ["displayText": text]]), accountID: id, collectedAt: time)
    }

    func testHourlyDollarsWinOverDailyPercentageAndCleaningRetainsExactWallet() throws {
        let text = "\u{001B}[32m**Amp Free:** $6/$10 remaining (replenishes +$0.5/hour)\u{001B}[0m\nAmp Free: 61% remaining today (resets daily)\nIndividual credits: $1,020.500000000000000001 remaining"
        let id = UUID(), snapshot = try parse(text, id: id)
        let free = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(free.id, "amp.free")
        XCTAssertEqual(free.usedPercentage, 40)
        XCTAssertEqual(free.remainingCount, 6)
        XCTAssertEqual(free.unit, "USD")
        XCTAssertNil(free.period)
        XCTAssertNil(free.resetsAt)
        XCTAssertEqual(free.resetSemantics, .continuousReplenishment)
        XCTAssertNil(free.nextReplenishmentAt)
        XCTAssertEqual(QuotaFormatting.nextEventLabel(free), "额度补充")
        XCTAssertEqual(QuotaFormatting.nextEventValue(free), "持续补充")
        XCTAssertEqual(snapshot.windows.last?.wallet?.total, Decimal(string: "1020.500000000000000001"))
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, time)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertEqual(Provider.amp.balancePresentation, .mixed)
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Fixture", provider: .amp), windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertNil(widget.displayMetrics.last?.ringFraction)
    }

    func testTierUsesActualUSDAndOrbHoursAndCalendarEndPrecision() throws {
        let text = "Amp Megawatt Tier: agent usage $18.57 of $20 remaining (93%), orb usage 732.8h of 750h a1.small orb hours remaining (98%) - period 2026-09-13 to 2026-10-13, resets upon renewal in 27 days"
        let snapshot = try parse(text)
        XCTAssertEqual(snapshot.providerPlanName, "Megawatt")
        XCTAssertEqual(snapshot.windows.map(\.id), ["amp.agent", "amp.orb"])
        XCTAssertEqual(try XCTUnwrap(snapshot.windows.first?.usedPercentage), 7.15, accuracy: 0.0000001)
        XCTAssertEqual(snapshot.windows.first?.unit, "USD")
        XCTAssertEqual(snapshot.windows.last?.unit, "小时")
        XCTAssertEqual(snapshot.windows.last?.remainingCount, 732.8)
        XCTAssertEqual(snapshot.windows.last?.totalCount, 750)
        for window in snapshot.windows {
            XCTAssertEqual(window.resetDatePrecision, .day)
            XCTAssertEqual(QuotaFormatting.nextEventValue(window), "2026-10-13")
            XCTAssertFalse(window.needsUpdate(at: Date(timeIntervalSince1970: 2_000_000_000)))
        }
    }

    func testLegacyDailyAndRoundedCountdownDoNotInventQuantityOrReset() throws {
        let snapshot = try parse("Amp Free: 61% remaining today (resets daily)\nSubscription Megawatt: 68% other usage and 97% orb usage remaining - resets upon renewal in 5 days\nWorkspace Fixture: $999 remaining")
        XCTAssertEqual(snapshot.windows.map(\.id), ["amp.free", "amp.agent", "amp.orb"])
        XCTAssertEqual(snapshot.windows.first?.usedPercentage, 39)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.resetsAt == nil && $0.totalCount == nil && $0.wallet == nil })
        XCTAssertNil(snapshot.windows.first?.resetSemantics)
        let duplicates = try parse("Amp Watt Tier: agent usage $8 of $10 remaining\nSubscription Watt: 90% other usage and 97% orb usage remaining")
        XCTAssertEqual(duplicates.windows.filter { $0.id == "amp.agent" }.count, 1)
        XCTAssertEqual(duplicates.windows.first?.usedPercentage, 20)
    }

    func testUnknownTextMalformedNumbersWrongOrbUnitsAndZeroLimitNeverInventQuota() throws {
        for text in ["Amp usage: 12 tokens", "Amp Free: 61% remaining", "Individual credits: $1,00 remaining", "Amp Free: $6/$10 remaining (refills sometime)", "Workspace Fixture: $20 remaining"] {
            XCTAssertThrowsError(try parse(text)) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        let unsupportedOrb = try parse("Amp Watt Tier: agent usage $8 of $10 remaining, orb usage 2d of 3d orb days remaining")
        XCTAssertEqual(unsupportedOrb.windows.map(\.id), ["amp.agent"])
        let noCap = try parse("Amp Watt Tier: agent usage $0 of $0 remaining\nIndividual credits: $0 remaining")
        XCTAssertEqual(noCap.windows.count, 1)
        XCTAssertEqual(noCap.windows.first?.wallet?.total, 0)
        let invalidDate = try parse("Amp Watt Tier: agent usage $8 of $10 remaining - period 2026-02-30 to 2026-03-02")
        XCTAssertNil(invalidDate.windows.first?.resetsAt)
        XCTAssertNil(invalidDate.windows.first?.resetDatePrecision)
    }

    func testStrictEnvelopeFlagsAndExpiredAccessTokenMessages() {
        for body in [#"{"ok":1,"result":{"displayText":"Individual credits: $1 remaining"}}"#,
                     #"{"ok":"true"}"#, #"{"ok":true,"result":{"displayText":42}}"#, "{}"] {
            XCTAssertThrowsError(try AmpProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: time)) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        XCTAssertThrowsError(try AmpProviderClient.snapshot(Data(#"{"ok":false,"error":{"code":"auth-required"}}"#.utf8), accountID: UUID(), collectedAt: time)) {
            XCTAssertEqual($0 as? RefreshFailure, .invalidCredential)
        }
        XCTAssertThrowsError(try parse("Please sign in to Amp")) { XCTAssertEqual($0 as? RefreshFailure, .invalidCredential) }
    }

    func testDirectReadOnlyRPCContractAccountIdentityAndHTTPFailures() async throws {
        let body = #"{"ok":true,"result":{"displayText":"Individual credits: $10 remaining"}}"#
        let transport = AmpTransport(body: body)
        let auth = ProviderAuthenticationController()
        XCTAssertEqual(auth.loginConfiguration(for: .amp).credentialLabel, "Amp Access Token")
        let id = UUID()
        let credential = try auth.credential(provider: .amp, apiKey: " token-a \n")
        let identity = try ProviderCredentialEnvelope.decode(credential, expectedProvider: .amp).sourceCredentialIdentity
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity, try ProviderCredentialEnvelope.decode(auth.credential(provider: .amp, apiKey: "token-a"), expectedProvider: .amp).sourceCredentialIdentity)
        XCTAssertNotEqual(identity, try ProviderCredentialEnvelope.decode(auth.credential(provider: .amp, apiKey: "token-b"), expectedProvider: .amp).sourceCredentialIdentity)
        let snapshot = try await ProviderQuotaClient(provider: .amp, transport: transport).quota(for: id, credential: credential)
        XCTAssertEqual(snapshot.accountID, id)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://ampcode.com/api/internal?userDisplayBalanceInfo")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-a")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, Data(#"{"method":"userDisplayBalanceInfo","params":{}}"#.utf8))
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do { _ = try await ProviderQuotaClient(provider: .amp, transport: AmpTransport(body: body, status: status)).quota(for: UUID(), credential: credential); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        let wrong = try auth.credential(provider: .commandCode, apiKey: "other")
        do { _ = try await ProviderQuotaClient(provider: .amp, transport: transport).quota(for: UUID(), credential: wrong); XCTFail("Wrong provider") }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
    }

    func testHourlyRefillRearmsBelowThresholdAndNeverProducesResetNotifications() throws {
        let id = UUID(), planner = NotificationPlanner()
        var ledger = ReminderLedger()
        var previous: QuotaSnapshot?
        for (index, remaining, expectedAlerts) in [(0, 0, 1), (1, 45, 0), (2, 10, 0), (3, 71, 0), (4, 69, 1)] {
            let parsed = try parse("Amp Free: $\(remaining)/$100 remaining (replenishes +$0.5/hour)", id: id)
            let time = Date(timeIntervalSince1970: Double(1000 + index))
            let snapshot = QuotaSnapshot(accountID: id, windows: parsed.windows, collectedAt: time)
            let result = planner.planSuccessfulRefresh(accountID: id, accountName: "Amp", previousSnapshot: previous,
                newSnapshot: snapshot, settings: AccountReminderSettings(thresholds: [30, 80, 100]), ledger: ledger, now: time)
            let notices = result.operations.compactMap { if case .deliver(let notice) = $0 { return notice }; return nil }
            XCTAssertEqual(notices.filter { $0.kind == .quotaAlert }.count, expectedAlerts)
            XCTAssertFalse(notices.contains { $0.kind == .confirmedReset || $0.kind == .expectedReset })
            XCTAssertFalse(result.operations.contains { if case .schedule = $0 { return true }; return false })
            ledger = result.ledger; previous = snapshot
        }
    }
}

private actor AmpTransport: ProviderTransport {
    let body: String
    let status: Int
    private var request: URLRequest?
    init(body: String, status: Int = 200) { self.body = body; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func lastRequest() -> URLRequest? { request }
}
