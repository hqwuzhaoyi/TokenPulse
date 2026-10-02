import Foundation
import XCTest
@testable import TokenPulse

final class CommandCodeProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_000)
    private let whoami = #"{"org":{"id":"org +&/test","login":"Fixture Org"},"orgLimits":[{"scope":"model","model":"model/a","modelLabel":"Model A","spent":"1","limit":"10","exceeded":false,"resetInterval":"daily","resetAt":"2026-10-03T00:00:00Z"}]}"#
    private let credits = #"{"credits":{"planId":"individual-ultra","monthlyCredits":"10.123456789012345678","purchasedCredits":2,"freeCredits":0},"windowLimits":{"limited":true,"fiveHour":{"used":"4","cap":"10","resetAt":1790985600000},"weekly":{"used":20,"cap":40}}}"#

    func testExactWalletRollingAndOrganizationLimitsWithoutPriceDerivedWindow() throws {
        let id = UUID()
        let snapshot = try CommandCodeProviderClient.snapshot(whoamiData: Data(whoami.utf8), creditsData: Data(credits.utf8),
                                                              accountID: id, collectedAt: time)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, time)
        XCTAssertEqual(snapshot.windows.count, 4)
        XCTAssertEqual(snapshot.windows.last?.wallet?.total, Decimal(string: "12.123456789012345678"))
        XCTAssertEqual(snapshot.windows.last?.wallet?.currency, "USD")
        XCTAssertNil(snapshot.windows.last?.usedPercentage)
        XCTAssertEqual(snapshot.windows.first?.usedPercentage, 40)
        XCTAssertEqual(snapshot.windows.first?.resetsAt, Date(timeIntervalSince1970: 1790985600))
        XCTAssertTrue(snapshot.windows.filter { $0.id.contains("org.") }.first?.id.contains("model/a") == true)
        XCTAssertFalse(snapshot.windows.contains { $0.id == "monthly" || $0.id == "credits" })
        XCTAssertEqual(snapshot.providerPlanName, "individual-ultra")
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Fixture", provider: .commandCode),
                                           windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 4)
        XCTAssertNotNil(widget.displayMetrics.first?.ringFraction)
        XCTAssertNil(widget.displayMetrics.last?.ringFraction)
    }

    func testMissingPotsAreUnknownAndDoNotBecomeZeroBalancesOrPlanDenominators() throws {
        let partial = #"{"credits":{"planId":"individual-pro","monthlyCredits":5},"windowLimits":{"limited":true,"fiveHour":{"used":1,"cap":10}}}"#
        let snapshot = try CommandCodeProviderClient.snapshot(whoamiData: Data("{}".utf8), creditsData: Data(partial.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil })
        XCTAssertThrowsError(try CommandCodeProviderClient.snapshot(whoamiData: Data("{}".utf8),
                                                                  creditsData: Data(#"{"credits":{"monthlyCredits":5}}"#.utf8),
                                                                  accountID: UUID(), collectedAt: time)) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
        let zeros = try CommandCodeProviderClient.snapshot(whoamiData: Data("{}".utf8),
            creditsData: Data(#"{"credits":{"monthlyCredits":0,"purchasedCredits":0,"freeCredits":0}}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(zeros.windows.first?.wallet?.total, 0)
    }

    func testStrictFlagsMalformedAmountsAndUnknownShapesFail() {
        for malformed in [
            #"{"credits":{"monthlyCredits":true,"purchasedCredits":0,"freeCredits":0}}"#,
            #"{"credits":{"monthlyCredits":"NaN","purchasedCredits":0,"freeCredits":0}}"#,
            #"{"windowLimits":{"limited":1,"fiveHour":{"used":1,"cap":10}}}"#,
            #"{"windowLimits":{"limited":"true","fiveHour":{"used":1,"cap":10}}}"#, "{}"
        ] {
            XCTAssertThrowsError(try CommandCodeProviderClient.snapshot(whoamiData: Data("{}".utf8), creditsData: Data(malformed.utf8), accountID: UUID(), collectedAt: time)) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        let invalidFlag = #"{"orgLimits":[{"spent":1,"limit":10,"exceeded":1}]}"#
        XCTAssertThrowsError(try CommandCodeProviderClient.snapshot(whoamiData: Data(invalidFlag.utf8), creditsData: Data(credits.utf8), accountID: UUID(), collectedAt: time))
    }

    func testLimitedFalseAndNonpositiveCapsNeverCreateFalseRings() throws {
        let body = #"{"credits":{"monthlyCredits":0,"purchasedCredits":1,"freeCredits":0},"windowLimits":{"limited":false,"fiveHour":{"used":100,"cap":10}}}"#
        let org = #"{"orgLimits":[{"spent":0,"limit":0},{"spent":2,"limit":-1},{"spent":2},{"spent":1,"limit":10,"exceeded":true}]}"#
        let snapshot = try CommandCodeProviderClient.snapshot(whoamiData: Data(org.utf8), creditsData: Data(body.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows.first?.isExhausted, true)
        XCTAssertEqual(snapshot.windows.first?.usedPercentage, 10)
        XCTAssertFalse(snapshot.windows.contains { $0.id == "commandCode.five-hour" })
    }

    func testOrganizationIdentitySurvivesReorderingAndResetChanges() throws {
        func parse(_ limits: String) throws -> [QuotaWindow] {
            try CommandCodeProviderClient.snapshot(whoamiData: Data(("{\"orgLimits\":\(limits)}").utf8), creditsData: Data(credits.utf8), accountID: UUID(), collectedAt: time).windows.filter { $0.id.contains("org.") }
        }
        let a = #"{"scope":"model","model":"a","spent":1,"limit":10,"resetInterval":"weekly"}"#
        let b = #"{"scope":"model","model":"b","spent":2,"limit":10,"resetInterval":"weekly","resetAt":"2026-10-10T00:00:00Z"}"#
        let first = try parse("[\(a),\(b)]")
        let second = try parse("[\(b),\(a)]")
        XCTAssertEqual(Set(first.map(\.id)), Set(second.map(\.id)))
        XCTAssertNotEqual(first[0].id, first[1].id)
    }

    func testRequestContractAndWhoamiFailureStopsFurtherRequests() async throws {
        let transport = CommandCodeTransport(whoami: whoami, credits: credits)
        let controller = ProviderAuthenticationController()
        let encoded = try controller.credential(provider: .commandCode, apiKey: " fixture-key \n")
        XCTAssertEqual(controller.loginConfiguration(for: .commandCode).credentialLabel, "Command Code API Key")
        let id = UUID()
        let snapshot = try await ProviderQuotaClient(provider: .commandCode, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(for: id, credential: encoded)
        XCTAssertEqual(snapshot.accountID, id)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.commandcode.ai/alpha/whoami?limits=1")
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems, [.init(name: "orgId", value: "org +&/test")])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
        for (status, failure) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            let failing = CommandCodeTransport(whoami: whoami, credits: credits, status: status)
            do { _ = try await ProviderQuotaClient(provider: .commandCode, transport: failing).quota(for: UUID(), credential: encoded); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? RefreshFailure, failure) }
            let captured = await failing.requests()
            XCTAssertEqual(captured.count, 1)
        }
    }

    @MainActor
    func testLocalAccountsPreserveCredentialIdentitySnapshotOnFailureAndDeletion() async throws {
        let suite = "command-code-fixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CommandCodeCredentials()
        let transport = CommandCodeTransport(whoami: whoami, credits: credits)
        let client = ProviderQuotaClient(provider: .commandCode, transport: transport)
        let monitor = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials,
                                   quotaClient: client, configurationStore: LocalAccountConfigurationStore(suiteName: suite),
                                   providerClient: { _ in client })
        let auth = ProviderAuthenticationController()
        await monitor.addAccount(name: "A", credential: try auth.credential(provider: .commandCode, apiKey: "key-a"), provider: .commandCode)
        await monitor.addAccount(name: "B", credential: try auth.credential(provider: .commandCode, apiKey: "key-b"), provider: .commandCode)
        XCTAssertEqual(monitor.states.count, 2)
        let a = try XCTUnwrap(monitor.states.first { $0.account.name == "A" })
        let b = try XCTUnwrap(monitor.states.first { $0.account.name == "B" })
        XCTAssertNotEqual(a.credentialIdentity, b.credentialIdentity)
        XCTAssertNotEqual(a.snapshot?.windows.last?.wallet?.total, b.snapshot?.windows.last?.wallet?.total)
        await transport.failKeyA()
        await monitor.refreshAll()
        let failed = try XCTUnwrap(monitor.states.first { $0.id == a.id })
        XCTAssertEqual(failed.lastFailure, .invalidCredential)
        XCTAssertEqual(failed.snapshot, a.snapshot)
        let persisted = try await LocalAccountStateStore(suiteName: suite).load()
        XCTAssertEqual(persisted, monitor.states)
        let encoded = try JSONEncoder().encode(monitor.configurations)
        XCTAssertEqual(try JSONDecoder().decode([AccountConfiguration].self, from: encoded), monitor.configurations)
        let deleted = await monitor.deleteAccount(accountID: a.id)
        XCTAssertTrue(deleted)
        let removed = await credentials.credential(for: a.id)
        XCTAssertNil(removed)
        XCTAssertEqual(monitor.states.map(\.id), [b.id])
    }
}

private actor CommandCodeTransport: ProviderTransport {
    private var captured: [URLRequest] = []
    let whoami: String
    let credits: String
    let status: Int
    private var failingKeyA = false
    init(whoami: String, credits: String, status: Int = 200) { self.whoami = whoami; self.credits = credits; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured.append(request)
        let key = request.value(forHTTPHeaderField: "Authorization")
        let body = request.url?.path == "/alpha/whoami" ? whoami : key == "Bearer key-b"
            ? #"{"credits":{"monthlyCredits":20,"purchasedCredits":0,"freeCredits":0}}"# : credits
        let code = failingKeyA && key == "Bearer key-a" ? 401 : status
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { captured }
    func failKeyA() { failingKeyA = true }
}

private actor CommandCodeCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { values[accountID] = credential }
    func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
