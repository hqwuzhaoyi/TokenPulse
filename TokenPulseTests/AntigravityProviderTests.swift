import Foundation
import XCTest
@testable import TokenPulse

final class AntigravityProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_000)
    private let summary = #"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"gemini-5h","displayName":"Gemini 组","window":"5h","remainingFraction":0.04,"resetTime":"2026-10-04T12:00:00Z"}]}]}"#

    func testInvalidConfiguredProjectFailsBeforeTokenExchangeWithInputMessage() async throws {
        let instant = time, transport = AntigravityFixtureTransport(summary: summary)
        let session = try GoogleNativeOAuth(clientID: antigravityFixtureClient, transport: transport, now: { instant }, requestedScopes: AntigravityProviderClient.scopes).begin(provider: .antigravity)
        let callback = URL(string: "\(session.callbackURL!)?code=fixture&state=\(session.state!)")!
        do {
            _ = try await AntigravityProviderClient(transport: transport, now: { instant }).authorize(callback: callback, session: session, accountID: UUID(), configuredProject: "my project!")
            XCTFail("Invalid project must fail before authorization exchange")
        } catch {
            guard case ProviderIntegrationError.unsupportedLogin(let message) = error else { return XCTFail("Expected project input feedback") }
            XCTAssertEqual(message, L10n.text("项目 ID 格式无效，请输入 Cloud 项目 ID；留空则使用已激活项目。"))
        }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testBlankGroupAndBucketNamesDoNotAddEmptyScopesOrLeadingWhitespace() throws {
        for group in ["", " \t\n "] {
            let data = try JSONSerialization.data(withJSONObject: ["groups": [["displayName": group, "buckets": [
                ["bucketId": "fallback", "displayName": " \t\n", "remainingFraction": 0.5],
                ["bucketId": "named", "displayName": "  Gemini  \n", "remainingFraction": 0.5]
            ]]]])
            let snapshot = try AntigravityProviderClient.snapshot(data, accountID: UUID(), collectedAt: time)
            XCTAssertNil(snapshot.windows[0].scope)
            XCTAssertEqual(snapshot.windows[0].displayName, "fallback")
            XCTAssertEqual(snapshot.windows[1].displayName, "Gemini")
        }
        let data = Data(#"{"groups":[{"displayName":"  Group  ","buckets":[{"bucketId":"b","displayName":"  Bucket  "}]}]}"#.utf8)
        XCTAssertEqual(try AntigravityProviderClient.snapshot(data, accountID: UUID(), collectedAt: time).windows.first?.displayName, "Group Bucket")
    }

    func testRealBucketsPreserveFractionInt64UnknownAndDisabledWithoutInventingUnits() throws {
        let data = Data(#"{"groups":[{"displayName":"Models","buckets":[{"bucketId":"ratio","window":"weekly","remainingFraction":0},{"bucketId":"amount","window":"future-window","remainingAmount":"9223372036854775807"},{"bucketId":"zero","remainingAmount":0},{"bucketId":"unknown"},{"bucketId":"disabled","disabled":true,"remainingFraction":0,"resetTime":"2026-10-04T12:00:00Z"}]}],"buckets":[{"bucketId":"deprecated","remainingFraction":0.5}]}"#.utf8)
        let snapshot = try AntigravityProviderClient.snapshot(data, accountID: UUID(), collectedAt: time)
        XCTAssertEqual(snapshot.windows.count, 5)
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 100)
        XCTAssertEqual(snapshot.windows[0].isExhausted, true)
        XCTAssertEqual(snapshot.windows[0].period, .weekly)
        XCTAssertEqual(snapshot.windows[1].exactCounts?.remaining, Decimal(string: "9223372036854775807"))
        XCTAssertNil(snapshot.windows[1].exactCounts?.total)
        XCTAssertNil(snapshot.windows[1].usedPercentage)
        XCTAssertEqual(snapshot.windows[1].period, .other)
        XCTAssertEqual(snapshot.windows[1].unit, "单位（类型未提供）")
        XCTAssertEqual(snapshot.windows[2].exactCounts?.remaining, 0)
        XCTAssertNil(snapshot.windows[3].usedPercentage)
        XCTAssertNil(snapshot.windows[3].exactCounts)
        XCTAssertNil(snapshot.windows[4].usedPercentage)
        XCTAssertNil(snapshot.windows[4].resetsAt)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil })
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let tiny = try AntigravityProviderClient.snapshot(Data(#"{"groups":[{"buckets":[{"bucketId":"tiny","remainingFraction":1e-17}]}]}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertLessThan(try XCTUnwrap(tiny.windows.first?.usedPercentage), 100)
        XCTAssertEqual(tiny.windows.first?.isExhausted, false)
    }

    func testMalformedOneofOverflowFractionAndResetDoNotProduceFakeQuota() {
        for bucket in [#"{"bucketId":"x","remainingFraction":1.1}"#, #"{"bucketId":"x","remainingFraction":-0.1}"#,
                       #"{"bucketId":"x","remainingFraction":"NaN"}"#, #"{"bucketId":"x","remainingFraction":true}"#,
                       #"{"bucketId":"x","remainingFraction":0.1,"remainingAmount":1}"#,
                       #"{"bucketId":"x","remainingAmount":"9223372036854775808"}"#,
                       #"{"bucketId":"x","remainingAmount":-1}"#, #"{"bucketId":"x","remainingAmount":true}"#,
                       #"{"bucketId":"x","remainingAmount":"1.5"}"#, #"{"bucketId":"x","resetTime":"bad"}"#] {
            XCTAssertThrowsError(try AntigravityProviderClient.snapshot(Data("{\"groups\":[{\"buckets\":[\(bucket)]}]}".utf8), accountID: UUID(), collectedAt: time))
        }
        XCTAssertThrowsError(try AntigravityProviderClient.snapshot(Data("{}".utf8), accountID: UUID(), collectedAt: time))
        let empty = try? AntigravityProviderClient.snapshot(Data(#"{"groups":[]}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(empty?.quotaStatusText, "未返回模型组额度")
        let legacy = try? AntigravityProviderClient.snapshot(Data(#"{"buckets":[{"bucketId":"old","remainingFraction":1}]}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(legacy?.windows.first?.usedPercentage, 0)
    }

    func testNativeAuthorizationDiscoversOnlyActivatedProjectAndValidatesQuota() async throws {
        let instant = time, id = UUID(), transport = AntigravityFixtureTransport(summary: summary)
        let auth = GoogleNativeOAuth(clientID: antigravityFixtureClient, transport: transport, now: { instant }, requestedScopes: AntigravityProviderClient.scopes)
        let session = try auth.begin(provider: .antigravity)
        let callback = URL(string: "\(session.callbackURL!)?code=fixture-code&state=\(session.state!)")!
        let encoded = try await AntigravityProviderClient(transport: transport, now: { instant })
            .authorize(callback: callback, session: session, accountID: id, configuredProject: nil)
        let envelope = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .antigravity)
        XCTAssertEqual(envelope.metadata["project"], "managed-project")
        XCTAssertEqual(envelope.metadata["localAccountID"], id.uuidString)
        XCTAssertEqual(envelope.accountID, "fixture-subject")
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 4)
        let load = try XCTUnwrap(requests.first { $0.url?.path == "/v1internal:loadCodeAssist" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: load.httpBody!) as? [String: Any])
        let metadata = try XCTUnwrap(body["metadata"] as? [String: String])
        XCTAssertEqual(metadata["ideType"], "IDE_UNSPECIFIED")
        XCTAssertEqual(metadata["ideName"], "TokenPulse")
        XCTAssertFalse(requests.contains { $0.url?.path.contains("onboard") == true })
        let quota = try XCTUnwrap(requests.last)
        XCTAssertEqual(quota.url?.absoluteString, "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")
        XCTAssertEqual(quota.httpMethod, "POST")
        XCTAssertEqual(quota.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
        XCTAssertFalse(quota.httpShouldHandleCookies)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: quota.httpBody!) as? [String: String], ["project": "managed-project"])
    }

    func testAllowedTiersAndProjectValidationErrorsDoNotAutoActivateOrReadQuota() async throws {
        for (load, failure) in [(#"{"allowedTiers":[{"id":"free-tier"}],"cloudaicompanionProject":"p"}"#, RefreshFailure.subscriptionRequired),
                                (#"{"currentTier":{"id":"active"},"projectValidationError":{"code":7}}"#, .insufficientPermissions)] {
            let instant = time, transport = AntigravityFixtureTransport(summary: summary, load: load)
            let auth = GoogleNativeOAuth(clientID: antigravityFixtureClient, transport: transport, now: { instant }, requestedScopes: AntigravityProviderClient.scopes)
            let session = try auth.begin(provider: .antigravity)
            do {
                _ = try await AntigravityProviderClient(transport: transport, now: { instant })
                    .authorize(callback: URL(string: "\(session.callbackURL!)?code=x&state=\(session.state!)")!, session: session, accountID: UUID(), configuredProject: nil)
                XCTFail("Expected entitlement refusal")
            } catch { XCTAssertEqual(error as? RefreshFailure, failure) }
            let requests = await transport.requests()
            XCTAssertEqual(requests.count, 3)
        }
    }

    func testExpiryRefreshPreservesIdentityAndReturnsRotationWhileWrongScopeIsRejected() async throws {
        let instant = time, id = UUID(), transport = AntigravityFixtureTransport(summary: summary)
        let client = AntigravityProviderClient(transport: transport, now: { instant })
        var envelope = try antigravityFixtureEnvelope(id: id, time: time)
        envelope.expiresAt = time.addingTimeInterval(-1)
        let result = try await client.quota(accountID: id, credential: envelope)
        let rotated = try ProviderCredentialEnvelope.decode(XCTUnwrap(result.updatedCredential), expectedProvider: .antigravity)
        XCTAssertEqual(rotated.accessToken, "fixture-access")
        XCTAssertEqual(rotated.metadata["sourceCredentialFingerprint"], envelope.metadata["sourceCredentialFingerprint"])
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, envelope.metadata["sourceCredentialFingerprint"])
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        let isolated = AntigravityFixtureTransport(summary: summary)
        for scenario in 0..<3 {
            var changed = try antigravityFixtureEnvelope(id: id, time: time)
            if scenario == 0 { changed.metadata["project"] = "other-project" }
            if scenario == 1 { changed.metadata["grantedScopes"] = GoogleNativeOAuth.scopes.joined(separator: " ") }
            do {
                _ = try await AntigravityProviderClient(transport: isolated, now: { instant }).quota(accountID: scenario == 2 ? UUID() : id, credential: changed)
                XCTFail("Expected identity/scope rejection")
            } catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let rejected = await isolated.requests()
        XCTAssertTrue(rejected.isEmpty)
    }

    @MainActor func testTwoAccountsFailureCacheRestartAndDeletion() async throws {
        let suite = "com.tokenpulse.tests.antigravity.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "cloudSyncEnabled")
        let credentials = WalletExpansionCredentials(), transport = AntigravityFixtureTransport(summary: summary)
        let instant = time, client = ProviderQuotaClient(provider: .antigravity, transport: transport, now: { instant })
        func monitor() -> QuotaMonitor {
            QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials, quotaClient: client,
                         configurationStore: LocalAccountConfigurationStore(suiteName: suite), providerClient: { _ in client })
        }
        let original = monitor(), a = UUID(), b = UUID()
        await original.start(refresh: false)
        await original.addAccount(name: "A", credential: try antigravityFixtureEnvelope(id: a, time: time).encoded(), provider: .antigravity, accountID: a)
        await original.addAccount(name: "B", credential: try antigravityFixtureEnvelope(id: b, time: time, project: "other-project").encoded(), provider: .antigravity, accountID: b)
        let previous = try XCTUnwrap(original.states.first { $0.id == a }?.snapshot)
        XCTAssertNotNil(original.states.first { $0.id == b }?.snapshot)
        await transport.fail()
        await original.refresh(accountID: a)
        XCTAssertEqual(original.states.first { $0.id == a }?.snapshot, previous)
        XCTAssertEqual(original.states.first { $0.id == a }?.lastFailure, .insufficientPermissions)
        XCTAssertNil(original.states.first { $0.id == b }?.lastFailure)
        let reopened = monitor(); await reopened.start(refresh: false)
        XCTAssertEqual(reopened.states, original.states)
        let deleted = await reopened.deleteAccount(accountID: a)
        XCTAssertTrue(deleted)
        let deletedKey = try await credentials.credential(for: a)
        XCTAssertNil(deletedKey)
        XCTAssertEqual(reopened.states.map(\.id), [b])
    }

    func testWidgetDemoAndQuotaReminderDoNotCreateWallet() throws {
        let account = SubscriptionAccount(name: "AG", provider: .antigravity)
        let snapshot = try AntigravityProviderClient.snapshot(Data(summary.utf8), accountID: account.id, collectedAt: time)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 1)
        XCTAssertNotNil(widget.displayMetrics.first?.ringFraction)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name,
            previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        let kinds = result.operations.compactMap { op -> ReminderNotificationKind? in
            if case .deliver(let value) = op { return value.kind }; return nil
        }
        XCTAssertEqual(kinds, [.quotaAlert])
        XCTAssertFalse(Provider.antigravity.hasWalletBalance)
        XCTAssertEqual(Provider.antigravity.iconAssetName, "ProviderAntigravity")
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .antigravity })
    }
}

private let antigravityFixtureClient = "12345-fixture.apps.googleusercontent.com"
private func antigravityFixtureEnvelope(id: UUID, time: Date, project: String = "managed-project") throws -> ProviderCredentialEnvelope {
    var envelope = ProviderCredentialEnvelope(provider: .antigravity, kind: .oauth, accessToken: "fixture-old", refreshToken: "fixture-refresh",
        expiresAt: time.addingTimeInterval(3_600), accountID: "fixture-subject",
        metadata: ["clientID": antigravityFixtureClient, "project": project, "localAccountID": id.uuidString,
                   "grantedScopes": AntigravityProviderClient.scopes.joined(separator: " ")])
    envelope.metadata["sourceCredentialFingerprint"] = try AntigravityProviderClient.fingerprint(envelope, accountID: id)
    return envelope
}
private actor AntigravityFixtureTransport: ProviderTransport {
    let summary: String
    let load: String
    private var received: [URLRequest] = []
    private var status = 200
    init(summary: String, load: String = #"{"currentTier":{"id":"active","name":"Fixture"},"cloudaicompanionProject":"managed-project"}"#) {
        self.summary = summary; self.load = load
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        received.append(request)
        let body: String
        if request.url?.host == "oauth2.googleapis.com" {
            body = "{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-new-refresh\",\"expires_in\":3600,\"token_type\":\"Bearer\",\"scope\":\"\(AntigravityProviderClient.scopes.joined(separator: " "))\"}"
        } else if request.url?.path == "/oauth2/v2/userinfo" { body = #"{"id":"fixture-subject"}"# }
        else if request.url?.path == "/v1internal:loadCodeAssist" { body = load }
        else { body = summary }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { received }
    func fail() { status = 403 }
}
