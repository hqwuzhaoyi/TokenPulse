import Foundation
import XCTest
@testable import TokenPulse

private actor KiroFixtureTransport: ProviderTransport {
    struct Reply: Sendable {
        let status: Int
        let data: Data
        var headers: [String: String] = ["Content-Type": "application/cbor"]
        var finalURL: URL? = nil
    }
    var replies: [Reply]
    var received: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        received.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = replies.removeFirst()
        return (reply.data, HTTPURLResponse(url: reply.finalURL ?? request.url!, statusCode: reply.status,
            httpVersion: nil, headerFields: reply.headers)!)
    }
    func requests() -> [URLRequest] { received }
}

final class KiroProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_000)
    private let profile = "arn:aws:codewhisperer:us-east-1:699475941385:profile/EHGA3GRVQMUK"
    private var page: String {
        #"<html><head><meta name="stage" content="prod"><meta name="user-status" content="active"><meta name="user-id" content="fixture-user"><meta name="idp" content="Google"><meta name="csrf-token" value="fixture-csrf"></head><body></body></html>"#
    }
    private var base: [String: KiroCBOR.Value] {
        ["resourceType": .string("CREDIT"), "displayNamePlural": .string("credits"), "unit": .string("credits"),
         "currentUsage": .number(10), "currentUsageWithPrecision": .number(10.125),
         "usageLimit": .number(100), "usageLimitWithPrecision": .number(100.5)]
    }
    private func root(_ items: [[String: KiroCBOR.Value]]) -> [String: KiroCBOR.Value] {
        ["usageBreakdownList": .array(items.map(KiroCBOR.Value.map)), "nextDateReset": .timestamp(5_000),
         "subscriptionInfo": .map(["subscriptionTitle": .string("Kiro Pro")])]
    }
    private func snapshot(_ items: [[String: KiroCBOR.Value]]) throws -> QuotaSnapshot {
        try KiroProviderParser.snapshot(root(items), accountID: UUID(), collectedAt: time)
    }
    private func session(_ id: UUID, remote: String = "fixture-user", origin: String = KiroProviderClient.origin,
                         expiresAt: Date? = nil) throws -> ProviderCredentialEnvelope {
        try WebProviderSession.credential(provider: .kiro, origin: origin, accountID: id, accessToken: "auth=fixture-cookie",
            expiresAt: expiresAt, remoteAccountID: remote, metadata: ["kiroProfileArn": profile, "kiroIdp": "Google",
                       "kiroCookieExpiries": expiresAt.map { "{\"auth\":\($0.timeIntervalSince1970)}" } ?? "{}"])
    }
    private func cbor(_ object: [String: KiroCBOR.Value], status: Int = 200, headers: [String: String]? = nil) throws -> KiroFixtureTransport.Reply {
        .init(status: status, data: try KiroCBOR.encode(.map(object)), headers: headers ?? ["Content-Type": "application/cbor"])
    }
    private var html: KiroFixtureTransport.Reply { .init(status: 200, data: Data(page.utf8), headers: ["Content-Type": "text/html"]) }
    private func hex(_ text: String) -> Data {
        let chars = Array(text); return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0+1]), radix: 16)! })
    }

    func testCBORIndependentFixturesCoverMapsArraysNumbersStrictBoolAndEpochTag() throws {
        let fixture = hex("a5616183666f6e65626f72f5f66162c11913886163f93e006164fa3f0000006165fb3ff4000000000000")
        let map = try XCTUnwrap(KiroCBOR.decode(fixture).object)
        XCTAssertEqual(map["a"], .array([.string("onebor"), .bool(true), .null]))
        XCTAssertEqual(map["b"]?.date, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(map["c"]?.numeric, 1.5); XCTAssertEqual(map["d"]?.numeric, 0.5); XCTAssertEqual(map["e"]?.numeric, 1.25)
        XCTAssertNil(KiroCBOR.Value.bool(true).numeric)
        XCTAssertEqual(try KiroCBOR.decode(hex("3b7fffffffffffffff")), .integer(Int64.min))
    }

    func testCBORRequestMatchesIndependentWireBytes() throws {
        let value: KiroCBOR.Value = .map(["origin": .string("KIRO_IDE"), "isEmailRequired": .bool(true)])
        XCTAssertEqual(try KiroCBOR.encode(value), hex("a26f6973456d61696c5265717569726564f5666f726967696e684b49524f5f494445"))
    }

    func testCBORBoundedIndefiniteContainersAndObservedAnonymousError() throws {
        let fixture = hex("bf61619f0102ff6162f5ff")
        XCTAssertEqual(try KiroCBOR.decode(fixture), .map(["a": .array([.integer(1), .integer(2)]), "b": .bool(true)]))
        let error = hex("bf665f5f747970657833636f6d2e616d617a6f6e2e6b69726f776562706f7274616c736572766963652342616452657175657374457863657074696f6e676d657373616765764353524620746f6b656e206973207265717569726564ff")
        XCTAssertEqual(try KiroCBOR.decode(error).object?["message"], .string("CSRF token is required"))
    }

    func testCBORRejectsDuplicateKeysOverflowTruncationNaNInvalidUTF8AndUnsupportedTags() {
        for text in ["a2616101616102", "bf616101616102ff", "a10101", "1bffffffffffffffff", "3bffffffffffffffff",
                     "a16161", "63fffeff", "fb7ff0000000000000", "fb7ff8000000000000", "fa7f800000", "f97c00",
                     "c001", "c4a20102", "41ff", "7f6161ff", "bf6161ff", "9f01", "ff", "0102", "f7", "c1f5"] {
            XCTAssertThrowsError(try KiroCBOR.decode(hex(text)), text)
        }
    }

    func testCBORLimitsBodyDepthStringsCollectionsAndNodeBudget() {
        XCTAssertThrowsError(try KiroCBOR.decode(Data(repeating: 0, count: 1_000_001)))
        XCTAssertThrowsError(try KiroCBOR.decode(Data(repeating: 0x81, count: 14) + Data([0])))
        XCTAssertThrowsError(try KiroCBOR.decode(hex("9a7fffffff")))
        XCTAssertThrowsError(try KiroCBOR.decode(hex("7a7fffffff")))
        XCTAssertThrowsError(try KiroCBOR.decode(Data([0x9f]) + Data(repeating: 0, count: 1_025) + Data([0xff])))
        XCTAssertThrowsError(try KiroCBOR.encode(.string(String(repeating: "x", count: 65_537))))
        XCTAssertThrowsError(try KiroCBOR.encode(.number(.infinity)))
    }

    func testOfficialPrecisionFieldsMonthlyCreditsAreQuotaNotMoney() throws {
        let result = try snapshot([base])
        let window = try XCTUnwrap(result.windows.first)
        XCTAssertEqual(window.remainingCount, 90.375); XCTAssertEqual(window.totalCount, 100.5)
        XCTAssertEqual(window.usedPercentage!, 10.125 / 100.5 * 100, accuracy: 0.000001)
        XCTAssertEqual(window.exactCounts?.used, Decimal(string: "10.125"))
        XCTAssertEqual(window.period, .monthly); XCTAssertEqual(window.resetsAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(window.unit, "credits"); XCTAssertNil(window.wallet)
        XCTAssertEqual(result.providerPlanName, "Kiro Pro")
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(result)), result)
    }

    func testMissingCountsRemainUnknownAndKnownZeroIsNotUnlimited() throws {
        var item = base; item.removeValue(forKey: "usageLimit"); item.removeValue(forKey: "usageLimitWithPrecision")
        let usedOnly = try snapshot([item]).windows[0]
        XCTAssertNil(usedOnly.usedPercentage); XCTAssertNil(usedOnly.remainingCount); XCTAssertNil(usedOnly.totalCount)
        XCTAssertEqual(usedOnly.exactCounts?.used, Decimal(string: "10.125")); XCTAssertNil(usedOnly.isExhausted)
        item = base; item["usageLimitWithPrecision"] = .integer(0)
        let zero = try snapshot([item]).windows[0]
        XCTAssertNil(zero.usedPercentage); XCTAssertEqual(zero.remainingCount, 0); XCTAssertFalse(zero.isUnlimited)
        XCTAssertEqual(zero.isExhausted, true)
    }

    func testActiveTrialBonusAndPurchasedCreditsHaveExpiryWithoutReset() throws {
        var item = base
        item["freeTrialInfo"] = .map(["freeTrialStatus": .string("ACTIVE"), "freeTrialExpiry": .timestamp(2_000),
                                     "currentUsage": .integer(2), "usageLimit": .integer(50)])
        item["bonuses"] = .array([.map(["status": .string("ACTIVE"), "bonusCode": .string("bonus-fixture"),
            "currentUsage": .integer(3), "usageLimit": .integer(100), "expiresAt": .timestamp(3_000)])])
        item["overageCredits"] = .array([.map(["currentUsage": .integer(4), "usageLimit": .integer(200), "expiresAt": .timestamp(4_000)])])
        let windows = try snapshot([item]).windows
        XCTAssertEqual(windows.count, 4)
        XCTAssertEqual(windows.dropFirst().map(\.expiresAt), [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 3_000), Date(timeIntervalSince1970: 4_000)])
        XCTAssertTrue(windows.dropFirst().allSatisfy { $0.period == nil && $0.resetsAt == nil && $0.resetSemantics == .nonResettingAllowance && $0.wallet == nil })
    }

    func testExpiredOrInactivePoolsAreNotDisplayedAndDuplicatesAreRejected() throws {
        var item = base
        item["freeTrialInfo"] = .map(["freeTrialStatus": .string("EXPIRED"), "currentUsage": .integer(1), "usageLimit": .integer(2)])
        item["bonuses"] = .array([.map(["status": .string("ACTIVE"), "bonusCode": .string("old"), "expiresAt": .timestamp(900)])])
        XCTAssertEqual(try snapshot([item]).windows.count, 1)
        XCTAssertThrowsError(try snapshot([base, base]))
        item["bonuses"] = .array(Array(repeating: .map(["status": .string("ACTIVE"), "bonusCode": .string("dup")]), count: 2))
        XCTAssertThrowsError(try snapshot([item]))
    }

    func testWrongTypesNegativeCountsAndUnusableResponseDoNotBecomeZero() throws {
        for bad: KiroCBOR.Value in [.bool(false), .string("100"), .number(-1), .array([])] {
            var item = base; item["usageLimitWithPrecision"] = bad
            XCTAssertThrowsError(try snapshot([item]))
        }
        var malformed = root([base]); malformed["nextDateReset"] = .integer(5_000)
        XCTAssertThrowsError(try KiroProviderParser.snapshot(malformed, accountID: UUID(), collectedAt: time))
        XCTAssertThrowsError(try KiroProviderParser.snapshot([:], accountID: UUID(), collectedAt: time))
        let empty = try KiroProviderParser.snapshot(root([]), accountID: UUID(), collectedAt: time)
        XCTAssertTrue(empty.windows.isEmpty); XCTAssertEqual(empty.quotaStatusText, "服务未提供可显示的额度池")
    }

    func testBootstrapBindsOfficialPersonalIdentityAndSocialProfile() throws {
        let identity = try KiroPortalIdentity.parse(Data(page.utf8))
        XCTAssertEqual(identity.userID, "fixture-user"); XCTAssertEqual(identity.profileArn, profile)
        XCTAssertEqual(identity.csrf, "fixture-csrf"); XCTAssertEqual(identity.idp, "Google")
        let builder = try KiroPortalIdentity.parse(Data(page.replacingOccurrences(of: "Google", with: "BuilderId").utf8))
        XCTAssertTrue(builder.profileArn.contains(":638616132270:profile/AAAACCCCXXXX"))
    }

    func testBootstrapRejectsAnonymousStaleEnterpriseDuplicateMetaAndHiddenMetadata() {
        for html in [page.replacingOccurrences(of: "active", with: "anonymous"), page.replacingOccurrences(of: "active", with: "stale"),
                     page.replacingOccurrences(of: "Google", with: "ExternalOIDC"), page.replacingOccurrences(of: "prod", with: "beta"),
                     page.replacingOccurrences(of: "</head>", with: #"<meta name="user-id" content="other"></head>"#),
                     "<head><!--\(page)--></head>", "<head><script>\(page)</script></head>", page.replacingOccurrences(of: "fixture-csrf", with: "bad&amp;csrf")] {
            XCTAssertThrowsError(try KiroPortalIdentity.parse(Data(html.utf8)))
        }
    }

    func testCookieCaptureDropsStatsUnrelatedDomainsAndExpiredScope() throws {
        func cookie(_ name: String, _ domain: String, _ path: String = "/", _ expires: Date? = nil) -> HTTPCookie {
            var fields: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: path, .secure: "TRUE"]
            if let expires { fields[.expires] = expires }; return HTTPCookie(properties: fields)!
        }
        let selection = try KiroProviderClient.cookiePolicy.select([cookie("auth", "app.kiro.dev"), cookie("_ga", "app.kiro.dev"),
            cookie("private", "github.com"), cookie("scoped", "app.kiro.dev", "/admin"), cookie("expired", "app.kiro.dev", "/", Date(timeIntervalSince1970: 900))], now: time)
        XCTAssertEqual(selection.header, "auth=fixture")
    }

    func testNativeRequestUsesCookieCSRFAndTransientTokenAtFixedOfficialScope() async throws {
        let id = UUID(), envelope = try session(id)
        let transport = try KiroFixtureTransport([html, cbor(["accessToken": .string("transient-token")]), cbor(root([base]))])
        let result = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope)
        XCTAssertEqual(result.snapshot.windows.count, 1); XCTAssertNil(result.updatedCredential)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.url!.host }, Array(repeating: "app.kiro.dev", count: 3))
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST", "POST"])
        XCTAssertEqual(requests[1].url!.path, "/service/KiroWebPortalService/operation/GetToken")
        XCTAssertEqual(requests[2].url!.path, "/service/KiroWebPortalService/operation/GetUserUsageAndLimits")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer transient-token")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Cookie"), "auth=fixture-cookie")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "X-CSRF-Token"), "fixture-csrf")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "smithy-protocol"), "rpc-v2-cbor")
        XCTAssertFalse(requests[2].httpShouldHandleCookies)
        let input = try KiroCBOR.decode(XCTUnwrap(requests[2].httpBody)).object
        XCTAssertEqual(input?["profileArn"], .string(profile)); XCTAssertEqual(input?["origin"], .string("KIRO_IDE"))
        XCTAssertEqual(input?["isEmailRequired"], .bool(true)); XCTAssertNil(input?["resourceType"])
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, try KiroProviderClient.sourceIdentity(envelope))
    }

    func testExpiredBearerRetriesOneNativeRefreshWithRotatedCSRF() async throws {
        let id = UUID(), envelope = try session(id)
        let transport = try KiroFixtureTransport([html, cbor(["accessToken": .string("old")]), cbor([:], status: 401),
            cbor(["accessToken": .string("new"), "csrfToken": .string("new-csrf"), "profileArn": .string(profile)]), cbor(root([base]))])
        _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 5); XCTAssertTrue(requests[3].url!.path.hasSuffix("/RefreshToken"))
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "X-CSRF-Token"), "fixture-csrf")
        XCTAssertEqual(try KiroCBOR.decode(XCTUnwrap(requests[3].httpBody)).object?["csrfToken"], .string("fixture-csrf"))
        XCTAssertEqual(requests[4].value(forHTTPHeaderField: "X-CSRF-Token"), "new-csrf")
        XCTAssertEqual(requests[4].value(forHTTPHeaderField: "Authorization"), "Bearer new")
    }

    func testGetTokenExpiryAlsoUsesOfficialRefreshAndCookieRotationReturnsBoundCredential() async throws {
        let id = UUID(), envelope = try session(id)
        let transport = try KiroFixtureTransport([html, cbor([:], status: 401),
            cbor(["accessToken": .string("new"), "csrfToken": .string("new-csrf")], headers: ["Content-Type": "application/cbor", "Set-Cookie": "auth=rotated; Path=/; Secure; HttpOnly"]), cbor(root([base]))])
        let result = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope)
        let updated = try ProviderCredentialEnvelope.decode(XCTUnwrap(result.updatedCredential), expectedProvider: .kiro)
        XCTAssertEqual(updated.accessToken, "auth=rotated"); XCTAssertNil(updated.refreshToken)
        XCTAssertEqual(updated.accountID, "fixture-user")
        XCTAssertFalse(try updated.encoded().contains("new-csrf")); XCTAssertFalse(try updated.encoded().contains("accessToken\":\"new\""))
        try WebProviderSession.validate(updated, provider: .kiro, accountID: id, origins: [KiroProviderClient.origin], now: time)
        let requests = await transport.requests(); XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Cookie"), "auth=rotated")
    }

    func testWrongLocalAccountOriginOrExpiredCookieStopsBeforeAnyRequest() async throws {
        let id = UUID()
        for envelope in [try session(UUID()), try session(id, origin: "https://other.invalid"), try session(id, expiresAt: Date(timeIntervalSince1970: 900))] {
            let transport = KiroFixtureTransport([])
            do { _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope); XCTFail("Unexpected success") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
            let requests = await transport.requests(); XCTAssertTrue(requests.isEmpty)
        }
    }

    func testDifferentPortalUserOrIdpCannotReplaceSavedScope() async throws {
        let id = UUID(), envelope = try session(id, remote: "other-user")
        let transport = KiroFixtureTransport([html])
        do { _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests(); XCTAssertEqual(requests.count, 1)
    }

    func testCrossOriginRedirectCannotReceiveAnotherOperation() async throws {
        let id = UUID(), envelope = try session(id)
        let transport = KiroFixtureTransport([.init(status: 200, data: Data(page.utf8), finalURL: URL(string: "https://other.invalid/")!)])
        do { _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests(); XCTAssertEqual(requests.count, 1)
    }

    func testInvalidRefreshProfileMissingSecretAndRepeated401CannotLoop() async throws {
        let id = UUID(), envelope = try session(id)
        for refresh in [["accessToken": KiroCBOR.Value.string("new"), "csrfToken": .string("new-csrf"), "profileArn": .string("other-profile")],
                        ["accessToken": .string("new")], ["accessToken": .string("bad\ntoken"), "csrfToken": .string("new-csrf")]] {
            let transport = try KiroFixtureTransport([html, cbor([:], status: 401), cbor(refresh)])
            do { _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope); XCTFail("Unexpected success") }
            catch { XCTAssertTrue([RefreshFailure.invalidCredential, .unreadableResponse].contains(error as? RefreshFailure ?? .network)) }
            let requests = await transport.requests(); XCTAssertEqual(requests.count, 3)
        }
        let transport = try KiroFixtureTransport([html, cbor(["accessToken": .string("old")]), cbor([:], status: 401),
            cbor(["accessToken": .string("new"), "csrfToken": .string("new-csrf")]), cbor([:], status: 401)])
        do { _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests(); XCTAssertEqual(requests.count, 5)
    }

    func testRateLimitAndWrongContentTypeFailWithoutInventedQuota() async throws {
        let id = UUID(), envelope = try session(id)
        for (reply, failure) in [(try cbor([:], status: 429), RefreshFailure.rateLimited),
                                 (try cbor(["accessToken": .string("x")], headers: ["Content-Type": "application/json"]), .unreadableResponse)] {
            let transport = KiroFixtureTransport([html, reply])
            do { _ = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope); XCTFail("Unexpected success") }
            catch { XCTAssertEqual(error as? RefreshFailure, failure) }
            let requests = await transport.requests(); XCTAssertEqual(requests.count, 2)
        }
    }

    func testRenewedCookieReplacesItsOldExpiryAndStableIdentitySurvivesRestart() async throws {
        let id = UUID(), envelope = try session(id, expiresAt: Date(timeIntervalSince1970: 1_200))
        let transport = try KiroFixtureTransport([html,
            cbor(["accessToken": .string("transient")], headers: ["Content-Type": "application/cbor",
                "Set-Cookie": "auth=renewed; Path=/; Secure; HttpOnly; Expires=Thu, 01 Jan 1970 01:00:00 GMT"]), cbor(root([base]))])
        let result = try await KiroProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1_000) }).quota(accountID: id, credential: envelope)
        let updated = try ProviderCredentialEnvelope.decode(XCTUnwrap(result.updatedCredential), expectedProvider: .kiro)
        XCTAssertEqual(updated.expiresAt, Date(timeIntervalSince1970: 3_600))
        XCTAssertEqual(updated.metadata["kiroCookieExpiries"], #"{"auth":3600}"#)
        XCTAssertEqual(try KiroProviderClient.sourceIdentity(updated), try KiroProviderClient.sourceIdentity(envelope))
        XCTAssertNotEqual(try WebProviderSession.fingerprint(updated), try WebProviderSession.fingerprint(envelope))
        let restoredTransport = try KiroFixtureTransport([html, cbor(["accessToken": .string("restored-token")]), cbor(root([base]))])
        let restored = try await KiroProviderClient(transport: restoredTransport, now: { Date(timeIntervalSince1970: 1_300) }).quota(accountID: id, credential: updated)
        XCTAssertEqual(restored.snapshot.sourceCredentialFingerprint, result.snapshot.sourceCredentialFingerprint)
        XCTAssertEqual(restored.snapshot.windows.count, 1)
    }

    func testCookieExpiryTableScopeMismatchCannotAuthenticateOrComputeStableIdentity() throws {
        let id = UUID()
        for table in [#"{"other":2000}"#, #"{"auth":2000}"#, #"{"auth":1.5}"#, #"{"auth":-1}"#, "not-json"] {
            let credential = try WebProviderSession.credential(provider: .kiro, origin: KiroProviderClient.origin, accountID: id,
                accessToken: "auth=fixture", remoteAccountID: "fixture-user", metadata: ["kiroProfileArn": profile, "kiroIdp": "Google", "kiroCookieExpiries": table])
            XCTAssertThrowsError(try KiroProviderClient.sourceIdentity(credential))
        }
    }

    #if os(iOS)
    @MainActor
    func testAccountClientMonitorAcceptsRotatedCookiePersistsAndRestoresStableScope() async throws {
        let id = UUID(), store = KiroMonitorStore()
        let envelope = try session(id, expiresAt: Date(timeIntervalSince1970: 1_200))
        let transport = try KiroFixtureTransport([html,
            cbor(["accessToken": .string("transient")], headers: ["Content-Type": "application/cbor",
                "Set-Cookie": "auth=renewed; Path=/; Secure; HttpOnly; Expires=Thu, 01 Jan 1970 01:00:00 GMT"]), cbor(root([base]))])
        let accountClient = AccountQuotaClient(provider: .kiro, credentialStore: store, transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) })
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: accountClient)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Kiro", credential: try envelope.encoded(), provider: .kiro, accountID: id)
        let state = try XCTUnwrap(monitor.states.first)
        XCTAssertNil(state.lastFailure); XCTAssertEqual(state.snapshot?.windows.count, 1)
        XCTAssertEqual(state.credentialIdentity, try KiroProviderClient.sourceIdentity(envelope))
        XCTAssertEqual(state.snapshot?.sourceCredentialFingerprint, state.credentialIdentity)
        let saved = await store.credential(for: id)
        let renewed = try ProviderCredentialEnvelope.decode(XCTUnwrap(saved), expectedProvider: .kiro)
        XCTAssertEqual(renewed.accessToken, "auth=renewed"); XCTAssertEqual(renewed.expiresAt, Date(timeIntervalSince1970: 3_600))
        XCTAssertEqual(renewed.sourceCredentialIdentity, envelope.sourceCredentialIdentity)
        let restoredTransport = try KiroFixtureTransport([html, cbor(["accessToken": .string("restored")]), cbor(root([base]))])
        let restored = QuotaMonitor(accountStore: store, credentialStore: store,
            quotaClient: AccountQuotaClient(provider: .kiro, credentialStore: store, transport: restoredTransport,
                now: { Date(timeIntervalSince1970: 1_300) }))
        await restored.start(refresh: false); XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: id)
        XCTAssertNil(restored.states.first?.lastFailure)
        XCTAssertEqual(restored.states.first?.snapshot?.collectedAt, Date(timeIntervalSince1970: 1_300))
        let snapshot = try XCTUnwrap(restored.states.first?.snapshot)
        let widget = WidgetAccountSnapshot(account: state.account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, snapshot.windows.count)
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .kiro })
        XCTAssertEqual(Provider.kiro.iconAssetName, "ProviderKiro")
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .kiro).method, .webSession)
        XCTAssertNotNil(Provider.kiro.webLoginProfile)
        let didDelete = await restored.deleteAccount(accountID: id); XCTAssertTrue(didDelete)
        let deleted = await store.credential(for: id); XCTAssertNil(deleted)
    }
    #endif
}

#if os(iOS)
private actor KiroMonitorStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials.removeValue(forKey: accountID) }
}
#endif
