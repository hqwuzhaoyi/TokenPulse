import Foundation
import XCTest
@testable import TokenPulse

final class IBMBobProviderTests: XCTestCase {
    private let profile = #"{"instances":[{"instance_id":"instance-one","instance_name":"Personal","user_id":"user-one","plan_name":"Pro+","refresh_at":1790812800,"region_domain":"us-east.bob.ibm.com","teams":[{"id":"team-one","name":"Solo","budget_limit":"40.000000000000000001"}]},{"instance_id":"instance-two","name":"Work","user_id":"user-two","plan_name":"Enterprise","refresh_at":"2026-10-05T00:00:00.000Z","region_domain":"api.eu-de.bob.ibm.com","teams":[{"id":"team-two","name":"Platform","budget_limit":160}]}]}"#

    private func jwt(expiry: Int = 4_102_444_800) -> String {
        func part(_ value: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
            return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return part(["alg": "RS256", "typ": "JWT"]) + "." + part(["exp": expiry, "sub": "synthetic-user"]) + ".synthetic-signature"
    }

    func testExplicitAPIKeyAndJWTModesHaveDifferentHeadersAndSafeEnvelopeIdentity() throws {
        let key = try IBMBobCredential("apikey:synthetic:key:colons")
        XCTAssertEqual(key.authorization, "Apikey synthetic:key:colons")
        XCTAssertNil(key.expiresAt)
        XCTAssertEqual(key.envelope().kind, .apiKey)
        let token = try IBMBobCredential("token:" + jwt())
        XCTAssertEqual(token.authorization, "Bearer " + jwt())
        XCTAssertEqual(token.envelope().kind, .session)
        XCTAssertNotNil(token.expiresAt)
        let restored = try ProviderCredentialEnvelope.decode(token.envelope().encoded(), expectedProvider: .ibmBob)
        XCTAssertEqual(restored.sourceCredentialIdentity, token.fingerprint)
        var changed = restored
        changed.accessToken = jwt(expiry: 4_102_444_799)
        XCTAssertNotEqual(changed.sourceCredentialIdentity, restored.sourceCredentialIdentity)
        let jwtAsKey = try IBMBobCredential("apikey:" + jwt())
        XCTAssertTrue(jwtAsKey.authorization.hasPrefix("Apikey "))
        for value in ["", "key-without-prefix", "apikey:", "token:", "bearer:value", "token:not-a-JWT", "apikey:two words", "apikey:secret\r\nHost:evil", "token:e30.e30.signature", "apikey:k\u{0}ey"] {
            XCTAssertThrowsError(try IBMBobCredential(value), value)
        }
        let encoded = try ProviderAuthenticationController().credential(provider: .ibmBob, apiKey: "apikey:synthetic")
        XCTAssertEqual(try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .ibmBob).kind, .apiKey)
        XCTAssertFalse(Provider.ibmBob.hasMonetaryWallet)
    }

    func testOnlyVerifiedRegionalHostsAreAllowedIncludingBareDomainNormalization() throws {
        XCTAssertEqual(try IBMBobProviderClient.regionalBase(nil), IBMBobProviderClient.home)
        XCTAssertEqual(try IBMBobProviderClient.regionalBase("US-EAST.BOB.IBM.COM."), IBMBobProviderClient.home)
        XCTAssertEqual(try IBMBobProviderClient.regionalBase("api.eu-de.bob.ibm.com").host, "api.eu-de.bob.ibm.com")
        for value in ["https://api.us-east.bob.ibm.com", "api.us-east.bob.ibm.com:443", "api.us-east.bob.ibm.com/path", "user@api.us-east.bob.ibm.com", "api.us-east.bob.ibm.com?key=x", "api.us-east.bob.ibm.com#x", "evil.example", "api.us-east.bob.ibm.com.evil.example", "api.unknown.bob.ibm.com", "api..bob.ibm.com", "api.us-east.bob.ibm.com\n.evil", "api.%75s-east.bob.ibm.com"] {
            XCTAssertThrowsError(try IBMBobProviderClient.regionalBase(value), value)
        }
    }

    func testInstancesAndTeamBudgetsRemainSeparateWithExactCountsAndIndependentResets() async throws {
        let transport = BobTransport(profile: profile, replies: ["team-one": (200, #"{"usage":"10.000000000000000001"}"#), "team-two": (200, #"{"usage":120,"budget_limit":160}"#)])
        let result = try await ProviderQuotaClient(provider: .ibmBob, transport: transport, now: { Date(timeIntervalSince1970: 100) }).quotaResult(for: UUID(), credential: IBMBobCredential("apikey:synthetic").envelope().encoded())
        XCTAssertEqual(result.snapshot.windows.count, 2)
        XCTAssertEqual(result.snapshot.collectedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(result.snapshot.providerPlanName, "Enterprise, Pro+")
        let first = result.snapshot.windows[0]
        let second = result.snapshot.windows[1]
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.scope, "Personal · Solo")
        XCTAssertEqual(second.scope, "Work · Platform")
        XCTAssertEqual(first.exactCounts?.used, Decimal(string: "10.000000000000000001"))
        XCTAssertEqual(first.exactCounts?.remaining, 30)
        XCTAssertEqual(first.exactCounts?.total, Decimal(string: "40.000000000000000001"))
        XCTAssertEqual(second.usedPercentage, 75)
        XCTAssertEqual(second.exactCounts?.used, 120)
        XCTAssertEqual(second.exactCounts?.remaining, 40)
        XCTAssertNotEqual(first.resetsAt, second.resetsAt)
        for window in result.snapshot.windows {
            XCTAssertEqual(window.period, .monthly)
            XCTAssertEqual(window.unit, "Bobcoins")
            XCTAssertNil(window.wallet)
            XCTAssertNil(window.isExhausted)
            XCTAssertNil(window.remainingCount)
            XCTAssertNil(window.totalCount)
        }
        let model = WidgetAccountSnapshot(account: SubscriptionAccount(name: "Bob", provider: .ibmBob), windows: result.snapshot.windows, collectedAt: result.snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(model.displayMetrics.count, 2)
        XCTAssertEqual(Set(model.displayMetrics.map(\.displayTitle)), Set([first.displayName, second.displayName]))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.us-east.bob.ibm.com/admin/v1/profile")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "x-instance-id"))
        XCTAssertEqual(requests[1].url?.absoluteString, "https://api.us-east.bob.ibm.com/admin/v1/teams/team-one/users/user-one")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-instance-id"), "instance-one")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-team-id"), "team-one")
        XCTAssertEqual(requests[2].url?.host, "api.eu-de.bob.ibm.com")
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == "Apikey synthetic" })
    }

    func testMissingOrExplicitNullBudgetKeepsUsageWithoutInventedZeroOrFraction() throws {
        let teams = try IBMBobProviderClient.descriptors(Data(profile.utf8))
        let null = try IBMBobProviderClient.window(Data(#"{"usage":"12.000000000000000001","budget_limit":null}"#.utf8), team: teams[0])
        XCTAssertEqual(null.exactCounts?.used, Decimal(string: "12.000000000000000001"))
        XCTAssertNil(null.exactCounts?.total)
        XCTAssertNil(null.exactCounts?.remaining)
        XCTAssertNil(null.usedPercentage)
        XCTAssertFalse(null.isUnlimited)
        XCTAssertTrue(QuotaFormatting.usage(null).hasPrefix("已用 "))
        XCTAssertNil(WidgetQuotaMetric(id: null.id, title: null.displayName, window: null).ringFraction)
        let noBudgetProfile = Data(#"{"instances":[{"instance_id":"instance","user_id":"user","teams":[{"id":"team"}]}]}"#.utf8)
        let unbudgeted = try XCTUnwrap(IBMBobProviderClient.descriptors(noBudgetProfile).first)
        let usageOnly = try IBMBobProviderClient.window(Data(#"{"usage":"12.5"}"#.utf8), team: unbudgeted)
        XCTAssertEqual(usageOnly.exactCounts?.used, Decimal(string: "12.5"))
        XCTAssertNil(usageOnly.exactCounts?.total)
        XCTAssertNil(usageOnly.exactCounts?.remaining)
        XCTAssertNil(usageOnly.usedPercentage)
        // Explicit null above overrides even a finite profile budget. A missing
        // detail budget may use the independently reported profile value.
        let missingDetail = try IBMBobProviderClient.window(Data(#"{"usage":10}"#.utf8), team: teams[0])
        XCTAssertNotNil(missingDetail.exactCounts?.total)
        let zero = try IBMBobProviderClient.window(Data(#"{"usage":12,"budget_limit":0}"#.utf8), team: teams[0])
        XCTAssertEqual(zero.exactCounts?.total, 0)
        XCTAssertNil(zero.usedPercentage)
        XCTAssertNil(zero.exactCounts?.remaining)
    }

    func testUnknownHostInLaterInstanceFailsBeforeAnyRegionalRequest() async throws {
        let unsafe = profile.replacingOccurrences(of: "api.eu-de.bob.ibm.com", with: "api.evil.example")
        let transport = BobTransport(profile: unsafe, replies: [:])
        do {
            _ = try await IBMBobProviderClient(transport: transport, now: { Date() }).quota(accountID: UUID(), credential: IBMBobCredential("apikey:synthetic").envelope())
            XCTFail("Untrusted regional host must fail")
        } catch { XCTAssertEqual(error as? RefreshFailure, .unreadableResponse) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.host, "api.us-east.bob.ibm.com")
        for badID in ["../outside", "team/name", "team%2Fname", "team?x", "team\r\nx-header:x"] {
            let bad = try JSONSerialization.data(withJSONObject: ["instances": [["instance_id": "instance", "user_id": "user", "teams": [["id": badID]]]]])
            XCTAssertThrowsError(try IBMBobProviderClient.descriptors(bad))
        }
        let duplicate = profile.replacingOccurrences(of: #"{"id":"team-one","name":"Solo","budget_limit":"40.000000000000000001"}"#, with: #"{"id":"team-one"},{"id":"team-one"}"#)
        XCTAssertThrowsError(try IBMBobProviderClient.descriptors(Data(duplicate.utf8)))
    }

    func testMalformedCountsFailAndNoSubscriptionIsDifferentFromNoBudget() async throws {
        let descriptor = try XCTUnwrap(IBMBobProviderClient.descriptors(Data(profile.utf8)).first)
        for body in ["{}", #"{"usage":null}"#, #"{"usage":true}"#, #"{"usage":-1}"#, #"{"usage":"NaN"}"#, #"{"usage":1,"budget_limit":false}"#, #"{"usage":1,"budget_limit":-1}"#] {
            XCTAssertThrowsError(try IBMBobProviderClient.window(Data(body.utf8), team: descriptor))
        }
        do {
            _ = try await IBMBobProviderClient(transport: BobTransport(profile: #"{"instances":[]}"#, replies: [:]), now: { Date() }).quota(accountID: UUID(), credential: IBMBobCredential("apikey:synthetic").envelope())
            XCTFail("No subscription must be distinguished")
        } catch { XCTAssertEqual(error as? RefreshFailure, .subscriptionRequired) }
        let transport = BobTransport(profile: profile, replies: ["team-one": (200, #"{"usage":1,"budget_limit":null}"#), "team-two": (200, #"{"usage":2,"budget_limit":null}"#)])
        let result = try await IBMBobProviderClient(transport: transport, now: { Date() }).quota(accountID: UUID(), credential: IBMBobCredential("apikey:synthetic").envelope())
        XCTAssertEqual(result.snapshot.windows.count, 2)
        XCTAssertTrue(result.snapshot.windows.allSatisfy { $0.usedPercentage == nil && $0.exactCounts?.total == nil })
    }

    func testJWTExpiryAndHTTPFailuresCannotMasqueradeAsNoBudget() async throws {
        let expiredTransport = BobTransport(profile: profile, replies: [:])
        do {
            _ = try await IBMBobProviderClient(transport: expiredTransport, now: { Date(timeIntervalSince1970: 100) }).quota(accountID: UUID(), credential: IBMBobCredential("token:" + jwt(expiry: 50)).envelope())
            XCTFail("Expired sign-in token must not be sent")
        } catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let sent = await expiredTransport.requests
        XCTAssertTrue(sent.isEmpty)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do {
                _ = try await IBMBobProviderClient(transport: BobTransport(profile: profile, replies: [:], profileStatus: status), now: { Date() }).quota(accountID: UUID(), credential: IBMBobCredential("apikey:synthetic").envelope())
                XCTFail("Expected HTTP failure")
            } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        let tokenTransport = BobTransport(profile: #"{"instances":[]}"#, replies: [:])
        do { _ = try await IBMBobProviderClient(transport: tokenTransport, now: { Date() }).quota(accountID: UUID(), credential: IBMBobCredential("token:" + jwt()).envelope()) }
        catch { XCTAssertEqual(error as? RefreshFailure, .subscriptionRequired) }
        let tokenRequests = await tokenTransport.requests
        XCTAssertEqual(tokenRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer " + jwt())
    }

    @MainActor
    func testRefreshFailureKeepsOldSourceButKeyChangeClearsItAndRestoresLocally() async throws {
        let suite = "com.tokenpulse.tests.bob.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let descriptor = try XCTUnwrap(IBMBobProviderClient.descriptors(Data(profile.utf8)).first)
        let window = try IBMBobProviderClient.window(Data(#"{"usage":10}"#.utf8), team: descriptor)
        let accounts = LocalAccountStateStore(suiteName: suite)
        let configurations = LocalAccountConfigurationStore(suiteName: suite)
        let credentials = BobMemoryCredentials()
        let query = BobLocalQuery(windows: [window])
        let monitor = QuotaMonitor(accountStore: accounts, credentialStore: credentials, quotaClient: query, configurationStore: configurations)
        await monitor.addAccount(name: "Bob", credential: try IBMBobCredential("apikey:first-synthetic").envelope().encoded(), provider: .ibmBob)
        let previous = try XCTUnwrap(monitor.states.first)
        await monitor.refresh(accountID: previous.id)
        XCTAssertEqual(monitor.states[0].snapshot, previous.snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
        await monitor.replaceCredential(try IBMBobCredential("apikey:second-synthetic").envelope().encoded(), accountID: previous.id)
        XCTAssertNil(monitor.states[0].snapshot)
        let restored = QuotaMonitor(accountStore: accounts, credentialStore: credentials, quotaClient: query, configurationStore: configurations)
        await restored.start(refresh: false)
        XCTAssertNil(restored.states[0].snapshot)
        XCTAssertEqual(restored.configuration(for: previous.id)?.credentialIdentity, monitor.configuration(for: previous.id)?.credentialIdentity)
        let deleted = await restored.deleteAccount(accountID: previous.id)
        XCTAssertTrue(deleted)
        let removed = await credentials.credential(for: previous.id)
        XCTAssertNil(removed)
    }

    func testIndependentBudgetAlertsAndUsageOnlyExpectedResetWithoutMoneyAlert() throws {
        let teams = try IBMBobProviderClient.descriptors(Data(profile.utf8))
        let finite = try IBMBobProviderClient.window(Data(#"{"usage":39,"budget_limit":40}"#.utf8), team: teams[0])
        let unknown = try IBMBobProviderClient.window(Data(#"{"usage":12,"budget_limit":null}"#.utf8), team: teams[1])
        let id = UUID()
        let snapshot = QuotaSnapshot(accountID: id, windows: [finite, unknown], collectedAt: Date(timeIntervalSince1970: 100))
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Bob", previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: snapshot.collectedAt)
        let deliveries = result.operations.compactMap { if case .deliver(let message) = $0 { return message }; return nil }
        XCTAssertEqual(deliveries.count, 1)
        XCTAssertEqual(deliveries.first?.kind, .quotaAlert)
        XCTAssertTrue(deliveries.first?.body.contains("Personal · Solo") == true)
        XCTAssertFalse(deliveries.first?.body.contains("Work · Platform") == true)
        let expected = result.operations.filter { if case .schedule = $0 { return true }; return false }
        XCTAssertEqual(expected.count, 2)
        let unknownOnly = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Bob", previousSnapshot: nil, newSnapshot: QuotaSnapshot(accountID: id, windows: [unknown], collectedAt: snapshot.collectedAt), settings: AccountReminderSettings(), ledger: ReminderLedger(), now: snapshot.collectedAt)
        XCTAssertFalse(unknownOnly.operations.contains { if case .deliver = $0 { return true }; return false })
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .ibmBob })
        let demo = DemoMode.snapshot(accountID: id, provider: .ibmBob)
        XCTAssertEqual(demo.windows.count, 2)
        XCTAssertTrue(demo.windows.allSatisfy { $0.wallet == nil && $0.unit == "Bobcoins" })
        XCTAssertNil(demo.windows.last?.usedPercentage)
    }
}

private actor BobTransport: ProviderTransport {
    let profile: String
    let replies: [String: (Int, String)]
    let profileStatus: Int
    var requests: [URLRequest] = []
    init(profile: String, replies: [String: (Int, String)], profileStatus: Int = 200) { self.profile = profile; self.replies = replies; self.profileStatus = profileStatus }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let key = request.value(forHTTPHeaderField: "x-team-id")
        let reply: (Int, String) = if let key { replies[key] ?? (500, "{}") } else { (profileStatus, profile) }
        return (Data(reply.1.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
    }
}
private actor BobMemoryCredentials: CredentialStoring {
    var keys: [UUID: String] = [:]
    func save(_ value: String, for id: UUID) { keys[id] = value }
    func credential(for id: UUID) -> String? { keys[id] }
    func deleteCredential(for id: UUID) { keys[id] = nil }
}
private actor BobLocalQuery: QuotaQuerying {
    let windows: [QuotaWindow]
    var calls = 0
    init(windows: [QuotaWindow]) { self.windows = windows }
    func quota(for id: UUID, credential: String) async throws -> QuotaSnapshot {
        calls += 1
        if calls > 1 { throw RefreshFailure.network }
        return QuotaSnapshot(accountID: id, windows: windows, collectedAt: Date(timeIntervalSince1970: 100))
    }
}
