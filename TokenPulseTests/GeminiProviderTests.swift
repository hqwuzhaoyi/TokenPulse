import Foundation
import XCTest
@testable import TokenPulse

final class GeminiProviderTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1000)
    private let load = #"{"currentTier":{"id":"standard-tier","name":"Code Assist"},"cloudaicompanionProject":"actual-project"}"#
    private let buckets = #"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.7,"resetTime":"2026-10-04T00:00:00Z"},{"modelId":"gemini-pro","remainingFraction":0.2,"resetTime":"2026-10-03T16:00:00Z"},{"modelId":"gemini-flash","remainingFraction":1}]}"#

    func testLimitingBucketKeepsItsOwnResetWithoutInventedPoolsOrPeriod() throws {
        let snapshot = try GeminiProviderClient.snapshot(Data(buckets.utf8), accountID: UUID(), collectedAt: instant)
        XCTAssertEqual(snapshot.windows.map(\.name), ["gemini-flash", "gemini-pro"])
        let pro = try XCTUnwrap(snapshot.windows.first { $0.name == "gemini-pro" })
        XCTAssertEqual(pro.usedPercentage, 80)
        XCTAssertEqual(pro.resetsAt, ProviderHTTP.isoDate("2026-10-03T16:00:00Z"))
        XCTAssertEqual(pro.period, .other)
        XCTAssertNil(pro.totalCount)
        XCTAssertNil(pro.exactCounts)
        XCTAssertNil(snapshot.wallet)
    }

    func testMissingUnknownBooleanFractionAndInvalidTimeNeverBecomeZero() throws {
        for input in ["{}", #"{"buckets":null}"#, #"{"buckets":[{}]}"#, #"{"buckets":[{"modelId":"m","remainingFraction":true}]}"#, #"{"buckets":[{"modelId":"m","remainingFraction":-0.1}]}"#, #"{"buckets":[{"modelId":"m","remainingFraction":1.1}]}"#, #"{"buckets":[{"modelId":"m","remainingFraction":0.5,"resetTime":"tomorrow"}]}"#, #"{"buckets":[{"modelId":"m","remainingAmount":"-1"}]}"#, #"{"buckets":[{"modelId":"m","remainingAmount":"NaN"}]}"#, #"{"buckets":[{"modelId":"m","remainingFraction":1e400}]}"#] {
            XCTAssertThrowsError(try GeminiProviderClient.snapshot(Data(input.utf8), accountID: UUID(), collectedAt: instant)) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        XCTAssertThrowsError(try GeminiProviderClient.snapshot(Data(#"{"buckets":[]}"#.utf8), accountID: UUID(), collectedAt: instant)) { XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows) }
    }

    func testExactAmountWithoutFractionIsPartialAndZeroFractionIsExhausted() throws {
        let result = try GeminiProviderClient.snapshot(Data(#"{"buckets":[{"modelId":"m","remainingAmount":"9007199254740993","tokenType":"tokens"},{"modelId":"n","remainingFraction":0}]}"#.utf8), accountID: UUID(), collectedAt: instant)
        XCTAssertEqual(result.windows[0].exactCounts?.remaining, Decimal(string: "9007199254740993"))
        XCTAssertNil(result.windows[0].usedPercentage)
        XCTAssertNil(result.windows[0].exactCounts?.total)
        XCTAssertEqual(result.windows[1].usedPercentage, 100)
        XCTAssertEqual(result.windows[1].isExhausted, true)
    }

    func testUncomparableAmountOnlyBucketsCannotBeMergedIntoFakeSharedPool() throws {
        XCTAssertThrowsError(try GeminiProviderClient.snapshot(Data(#"{"buckets":[{"modelId":"m","remainingAmount":"5","tokenType":"requests"},{"modelId":"m","remainingAmount":"100","tokenType":"tokens"}]}"#.utf8), accountID: UUID(), collectedAt: instant))
    }

    func testProjectAndTruthfulMetadataAreSentBeforeReadOnlyQuota() async throws {
        let now = instant, id = UUID(), transport = GeminiFixtureTransport([(200, load), (200, buckets)])
        let envelope = credential(id: id)
        let result = try await ProviderQuotaClient(provider: .gemini, transport: transport, now: { now }).quotaResult(for: id, credential: envelope.encoded())
        XCTAssertEqual(result.snapshot.providerPlanName, "Code Assist")
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, try GeminiProviderClient.fingerprint(envelope))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1internal:loadCodeAssist", "/v1internal:retrieveUserQuota"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && !$0.httpShouldHandleCookies })
        let discovery = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        let metadata = try XCTUnwrap(discovery["metadata"] as? [String: String])
        XCTAssertEqual(metadata["ideType"], "IDE_UNSPECIFIED")
        XCTAssertEqual(metadata["platform"], "PLATFORM_UNSPECIFIED")
        XCTAssertEqual(metadata["pluginType"], "PLUGIN_UNSPECIFIED")
        XCTAssertEqual(metadata["ideName"], "TokenPulse")
        let quota = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: String])
        XCTAssertEqual(quota, ["project": "actual-project"])
    }

    func testManagedDiscoveryAndConfiguredFallbackRequireAnActivatedTier() async throws {
        let now = instant
        for (body, configured, expected) in [(load, nil, "actual-project"), (#"{"currentTier":{"id":"standard-tier"}}"#, "own-project", "own-project")] as [(String, String?, String)] {
            let result = try await GeminiProviderClient(transport: GeminiFixtureTransport([(200, body)]), now: { now }).discoverProject(token: "synthetic", configuredProject: configured)
            XCTAssertEqual(result.id, expected)
        }
        for body in [#"{"allowedTiers":[{"id":"free-tier","isDefault":true}],"cloudaicompanionProject":"actual-project"}"#, #"{"currentTier":{"id":"standard-tier"}}"#] {
            do { _ = try await GeminiProviderClient(transport: GeminiFixtureTransport([(200, body)]), now: { now }).discoverProject(token: "synthetic", configuredProject: nil); XCTFail("Do not onboard or guess project") }
            catch { XCTAssertEqual(error as? RefreshFailure, .googleProjectRequired) }
        }
    }

    func testDifferentResolvedProjectFailsBeforeQuotaAndDoesNotChangeIdentity() async throws {
        let now = instant, id = UUID(), transport = GeminiFixtureTransport([(200, load.replacingOccurrences(of: "actual-project", with: "different-project"))])
        do { _ = try await GeminiProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: credential(id: id)); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .googleProjectRequired) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testCredentialIdentitySurvivesTokenRefreshButChangesWithClientSubjectProjectAndLocalAccount() throws {
        let old = credential(id: UUID()), identity = try GeminiProviderClient.fingerprint(old)
        var token = old; token.accessToken = "new-access"; token.refreshToken = "new-refresh"
        XCTAssertEqual(try GeminiProviderClient.fingerprint(token), identity)
        for field in ["clientID", "project", "localAccountID", "subject"] {
            var changed = old
            switch field {
            case "clientID": changed.metadata[field] = "999-new.apps.googleusercontent.com"
            case "localAccountID": changed.metadata[field] = UUID().uuidString
            case "subject": changed.accountID = "different-subject"
            default: changed.metadata[field] = "other-project"
            }
            XCTAssertNotEqual(try GeminiProviderClient.fingerprint(changed), identity)
        }
        var spoof = old; spoof.metadata["sourceCredentialFingerprint"] = "claimed-old"
        XCTAssertEqual(spoof.sourceCredentialIdentity, identity)
    }

    func testAccountMismatchAndExpiredAccessTokenRejectBeforeTransport() async throws {
        let now = instant, id = UUID(), transport = GeminiFixtureTransport([]), client = GeminiProviderClient(transport: transport, now: { now })
        for mismatch in [true, false] {
            var envelope = credential(id: id)
            if !mismatch { envelope.expiresAt = now }
            do { _ = try await client.quota(accountID: mismatch ? UUID() : id, credential: envelope); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testUnsupportedClientAndProjectPermissionHaveActionableDistinctFailures() async throws {
        let now = instant
        for (status, body, failure) in [(403, #"{"error":{"details":[{"reason":"UNSUPPORTED_CLIENT"}]}}"#, RefreshFailure.googleClientUnsupported), (403, #"{"error":{"status":"PERMISSION_DENIED"}}"#, .googleProjectRequired), (429, "{}", .rateLimited)] {
            do { _ = try await GeminiProviderClient(transport: GeminiFixtureTransport([(status, body)]), now: { now }).discoverProject(token: "synthetic", configuredProject: nil); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, failure) }
        }
    }

    func testWatchCompatibleOfflineRefreshRetainsIdentityAndRotatedCredential() async throws {
        let now = instant, id = UUID()
        var envelope = credential(id: id); envelope.expiresAt = now
        let transport = GeminiFixtureTransport([(200, #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#)])
        let refreshed = try await ProviderAuthenticationController(transport: transport, now: { now }).refreshCredentialIfNeeded(provider: .gemini, credential: envelope.encoded())
        XCTAssertTrue(refreshed.changed)
        let result = try ProviderCredentialEnvelope.decode(refreshed.credential, expectedProvider: .gemini)
        XCTAssertEqual(result.refreshToken, "new-refresh")
        XCTAssertEqual(result.sourceCredentialIdentity, envelope.sourceCredentialIdentity)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertFalse(String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8)!.contains("client_secret"))
    }

    func testProviderRegistrationWidgetDemoAndOAuthRouting() throws {
        XCTAssertTrue(Provider.allCases.contains(.gemini))
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .gemini).method, .authorizationCode)
        XCTAssertEqual(Provider.gemini.iconAssetName, "ProviderGemini")
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .gemini })
        let snapshot = try GeminiProviderClient.snapshot(Data(buckets.utf8), accountID: UUID(), collectedAt: instant)
        let widget = WidgetAccountSnapshot(account: .init(id: snapshot.accountID, name: "Gemini", provider: .gemini), windows: snapshot.windows, collectedAt: instant, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertTrue(widget.displayMetrics.allSatisfy { $0.window != nil })
    }

    private func credential(id: UUID) -> ProviderCredentialEnvelope {
        .init(provider: .gemini, kind: .oauth, accessToken: "synthetic-access", refreshToken: "synthetic-refresh", expiresAt: instant.addingTimeInterval(3600), accountID: "google-subject", metadata: ["clientID": "123-test.apps.googleusercontent.com", "grantedScopes": GoogleNativeOAuth.scopes.joined(separator: " "), "localAccountID": id.uuidString, "project": "actual-project", "googleNativeFormat": "v1"])
    }
}

private actor GeminiFixtureTransport: ProviderTransport {
    var requests: [URLRequest] = []
    var replies: [(Int, String)]
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw ProviderIntegrationError.server }
        let reply = replies.removeFirst()
        return (Data(reply.1.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
    }
}
