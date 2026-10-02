import Foundation
import XCTest
@testable import TokenPulse

final class NotionAIProviderTests: XCTestCase {
    private let spaces = #"{"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee":{"notion_user":{"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee":{"value":{"value":{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","email":"person@example.com","name":"Example Person"}}}},"space":{"00000000-7777-8888-9999-aaaaaaaaaaaa":{"value":{"value":{"id":"00000000-7777-8888-9999-aaaaaaaaaaaa","name":"Personal","plan_type":"personal","subscription_tier":"free"}}},"11111111-2222-3333-4444-555555555555":{"value":{"value":{"id":"11111111-2222-3333-4444-555555555555","name":"Acme","plan_type":"team","subscription_tier":"business"}}}}}}"#
    private let rate = #"{"status":"within_limit","window":{"creditType":"basic_ai_credits","scope":"per_user","window":"6h","used":42.5,"limit":100},"resetsInSeconds":12600,"billingPeriodWindow":{"creditType":"basic_ai_credits","scope":"per_user","cadence":"billing_period","used":18.0,"limit":100,"periodEndMs":1788000000000},"enforcement":"preview"}"#
    private let userID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    private let workspaceID = "11111111-2222-3333-4444-555555555555"
    func testExplicitWorkspaceChoicesKeepFreeAndBusinessInsteadOfChoosingFirstPaid() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let choices = try await NotionAIProviderClient.credentialChoices([sessionQuotaCookie("token_v2", domain: ".notion.com")],
            accountID: id, now: now, transport: SessionQuotaTransport([(200, spaces)]))
        XCTAssertEqual(choices.map(\.id), ["00000000-7777-8888-9999-aaaaaaaaaaaa", workspaceID])
        let free = try ProviderCredentialEnvelope.decode(choices[0].credential, expectedProvider: .notionAI)
        let business = try ProviderCredentialEnvelope.decode(choices[1].credential, expectedProvider: .notionAI)
        XCTAssertEqual(free.metadata["workspaceID"], choices[0].id)
        XCTAssertEqual(business.metadata["workspaceID"], workspaceID)
        XCTAssertEqual(business.accountID, userID)
        XCTAssertNotEqual(free.metadata["sourceCredentialFingerprint"], business.metadata["sourceCredentialFingerprint"])
        XCTAssertTrue(choices[0].title.contains("Personal"))
    }
    func testQueryOnlySelectedWorkspaceUsesOriginAndSourceFingerprint() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let envelope = try WebProviderSession.credential(provider: .notionAI, origin: NotionAIProviderClient.origin, accountID: id,
            accessToken: "token_v2=fixture", remoteAccountID: userID, metadata: ["workspaceID": workspaceID])
        let transport = SessionQuotaTransport([(200, spaces), (200, rate)])
        let result = try await NotionAIProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: envelope)
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, envelope.metadata["sourceCredentialFingerprint"])
        XCTAssertEqual(result.snapshot.windows.count, 2)
        XCTAssertTrue(result.snapshot.windows.allSatisfy { $0.id.contains(workspaceID) && $0.name.contains("Acme") })
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.path), ["/api/v3/getSpaces", "/api/v3/getCreditRateLimitStatus"])
        let body = try XCTUnwrap(requests.last?.httpBody)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body), ["spaceId": workspaceID])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Cookie") == "token_v2=fixture" && $0.value(forHTTPHeaderField: "Origin") == NotionAIProviderClient.origin && !$0.httpShouldHandleCookies })
    }
    func testRollingAndBillingCountsPreserveReportedDurationsUnitsAndMissingAmounts() throws {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = try NotionAIProviderClient.snapshot(Data(rate.utf8), accountID: UUID(), workspaceID: workspaceID, collectedAt: now)
        XCTAssertEqual(snapshot.windows[0].name, "6 小时 AI 额度")
        XCTAssertEqual(snapshot.windows[0].period, .other)
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 42.5)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "42.5"))
        XCTAssertEqual(snapshot.windows[0].resetsAt, now.addingTimeInterval(12600))
        XCTAssertEqual(snapshot.windows[1].usedPercentage, 18)
        XCTAssertEqual(snapshot.windows[1].period, .monthly, "The official usage documentation establishes a monthly billing allowance")
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil && $0.unit == "AI credits" })
        let partial = try NotionAIProviderClient.snapshot(Data(#"{"window":{"used":"1.234567890123456789","window":"unknown"}}"#.utf8), accountID: UUID(), workspaceID: workspaceID, collectedAt: now)
        XCTAssertEqual(partial.windows.first?.exactCounts?.used, Decimal(string: "1.234567890123456789"))
        XCTAssertNil(partial.windows.first?.usedPercentage)
        XCTAssertNil(partial.windows.first?.exactCounts?.total)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }
    func testNotApplicableIsSuccessfulStateDistinctFromUnreadableOrWrongCreditType() throws {
        let noPlan = try NotionAIProviderClient.snapshot(Data(#"{"status":"not_applicable"}"#.utf8), accountID: UUID(), workspaceID: workspaceID, collectedAt: Date())
        XCTAssertTrue(noPlan.windows.isEmpty)
        XCTAssertEqual(noPlan.quotaStatusText, "所选工作区没有适用的 Notion AI 额度")
        for body in ["{}", #"{"window":{"used":true,"limit":100}}"#, #"{"window":{"used":"NaN","limit":100}}"#,
                     #"{"window":{"creditType":"custom_agent_credits","used":1,"limit":100}}"#] {
            XCTAssertThrowsError(try NotionAIProviderClient.snapshot(Data(body.utf8), accountID: UUID(), workspaceID: workspaceID, collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }
    func testForeignOrRemovedWorkspaceAndAmbiguousUserCannotMixScopes() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let envelope = try WebProviderSession.credential(provider: .notionAI, origin: NotionAIProviderClient.origin, accountID: id,
            accessToken: "token_v2=fixture", remoteAccountID: userID, metadata: ["workspaceID": "99999999-1111-2222-3333-444444444444"])
        let transport = SessionQuotaTransport([(200, spaces), (200, rate)])
        do { _ = try await NotionAIProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: envelope); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests(); XCTAssertEqual(requests.count, 1)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(spaces.utf8)) as? [String: Any])
        let otherID = "bbbbbbbb-1111-2222-3333-444444444444"
        root[otherID] = ["notion_user": [otherID: ["value": ["id": otherID]]], "space": [:]]
        XCTAssertThrowsError(try NotionAIProviderClient.parseWorkspaces(JSONSerialization.data(withJSONObject: root)))
    }
    func testLegacyNotionSoCookieAndTamperedWorkspaceMetadataAreRejected() async {
        do { _ = try await NotionAIProviderClient.credentialChoices([sessionQuotaCookie("token_v2", domain: "notion.so")],
                                                                   accountID: UUID(), now: Date(), transport: SessionQuotaTransport([])); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        do {
            let id = UUID(), now = Date(timeIntervalSince1970: 100)
            var envelope = try WebProviderSession.credential(provider: .notionAI, origin: NotionAIProviderClient.origin, accountID: id,
                accessToken: "token_v2=fixture", remoteAccountID: userID, metadata: ["workspaceID": workspaceID])
            envelope.metadata["workspaceID"] = "00000000-7777-8888-9999-aaaaaaaaaaaa"
            let transport = SessionQuotaTransport([])
            do { _ = try await NotionAIProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: envelope); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
            let requests = await transport.requests(); XCTAssertTrue(requests.isEmpty)
        } catch { XCTFail("Fixture construction failed") }
    }
}
