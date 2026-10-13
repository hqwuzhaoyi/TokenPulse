import XCTest
@testable import TokenPulse

final class ElevenLabsProviderTests: XCTestCase {
    func testUnrepresentableResetTimeIsNotUsedForScheduling() throws {
        let body = #"{"character_count":960,"character_limit":1000,"next_character_count_reset_unix":1e20}"#
        let window = try XCTUnwrap(ElevenLabsProviderClient.windows(Data(body.utf8)).first)
        XCTAssertNil(window.resetsAt)
        XCTAssertEqual(window.usedPercentage, 96)
    }

    func testKeyHeaderAndIndependentAccounts() async throws {
        let transport = ElevenLabsTransportStub(status: 200, body: #"{"character_count":120,"character_limit":1000,"next_character_count_reset_unix":2000}"#)
        let controller = ProviderAuthenticationController(transport: transport)
        let client = ProviderQuotaClient(provider: .elevenLabs, transport: transport,
                                         now: { Date(timeIntervalSince1970: 100) })
        let first = UUID(), second = UUID()
        for (id, key) in [(first, "fixture-first"), (second, "fixture-second")] {
            let credential = try controller.credential(provider: .elevenLabs, apiKey: key)
            let result = try await client.quotaResult(for: id, credential: credential)
            XCTAssertEqual(result.snapshot.accountID, id)
            XCTAssertEqual(result.snapshot.collectedAt, Date(timeIntervalSince1970: 100))
            let window = try XCTUnwrap(result.snapshot.windows.first)
            XCTAssertEqual(window.usedPercentage, 12)
            XCTAssertEqual(window.remainingCount, 880)
            XCTAssertEqual(window.totalCount, 1000)
            XCTAssertEqual(window.unit, "字符")
            XCTAssertNil(window.period, "A billing end does not establish a fixed month")
            XCTAssertEqual(window.resetsAt, Date(timeIntervalSince1970: 2000))
        }
        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "xi-api-key") }, ["fixture-first", "fixture-second"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertTrue(requests.allSatisfy { $0.url?.absoluteString == "https://api.elevenlabs.io/v1/user/subscription" })
        XCTAssertEqual(controller.loginConfiguration(for: .elevenLabs).method, .apiKey)
    }

    func testMissingPermissionDiffersFromInvalidKeyAndRateLimit() async throws {
        let examples: [(Int, String, RefreshFailure)] = [
            (401, #"{"detail":{"status":"missing_permissions"}}"#, .insufficientPermissions),
            (403, #"{"detail":{"status":"missing_permissions"}}"#, .insufficientPermissions),
            (401, #"{"detail":{"status":"invalid_api_key"}}"#, .invalidCredential),
            (429, "{}", .rateLimited),
            (500, "{}", .server),
        ]
        for (status, body, expected) in examples {
            let client = ProviderQuotaClient(provider: .elevenLabs,
                                             transport: ElevenLabsTransportStub(status: status, body: body))
            let credential = try ProviderAuthenticationController().credential(provider: .elevenLabs, apiKey: "fixture")
            do {
                _ = try await client.quotaResult(for: UUID(), credential: credential)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
        }
    }

    func testMissingOrZeroAllowanceDoesNotBecomeZeroUsage() throws {
        for body in ["{}", #"{"character_limit":1000}"#, #"{"character_count":0,"character_limit":0}"#,
                     #"{"character_count":-1,"character_limit":1000}"#, #"{"voice_slots_used":5,"voice_limit":10}"#] {
            XCTAssertTrue(try ElevenLabsProviderClient.windows(Data(body.utf8)).isEmpty)
        }
        XCTAssertThrowsError(try ElevenLabsProviderClient.windows(Data(#"{"character_count":true,"character_limit":1000}"#.utf8)))
        XCTAssertThrowsError(try ElevenLabsProviderClient.windows(Data("[]".utf8)))
    }

    func testZeroUsageAndOverageArePreservedWithoutInventingReset() throws {
        for (used, expected) in [(0, 0.0), (1200, 120.0)] {
            let body = "{\"character_count\":\(used),\"character_limit\":1000}"
            let window = try XCTUnwrap(ElevenLabsProviderClient.windows(Data(body.utf8)).first)
            XCTAssertEqual(window.usedPercentage, expected)
            XCTAssertEqual(window.isExhausted, used >= 1000)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(window.wallet)
            let restored = try JSONDecoder().decode(QuotaWindow.self, from: JSONEncoder().encode(window))
            XCTAssertEqual(restored, window)
        }
    }

    func testWidgetsAndNotificationsUseTheCharacterWindow() throws {
        let account = SubscriptionAccount(name: "Voice", provider: .elevenLabs)
        let windows = try ElevenLabsProviderClient.windows(Data(#"{"character_count":960,"character_limit":1000,"next_character_count_reset_unix":2000}"#.utf8))
        let snapshot = QuotaSnapshot(accountID: account.id, windows: windows, collectedAt: Date(timeIntervalSince1970: 100))
        let widget = WidgetAccountSnapshot(account: account, windows: windows,
                                           collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 1)
        XCTAssertEqual(widget.displayMetrics.first?.window?.unit, "字符")
        let plan = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name,
            previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(),
            ledger: ReminderLedger(), now: snapshot.collectedAt)
        XCTAssertTrue(plan.operations.contains {
            if case .deliver(let notification) = $0 { return notification.kind == .quotaAlert }
            return false
        })
        XCTAssertFalse(plan.operations.contains {
            if case .deliver(let notification) = $0 { return notification.kind == .walletAlert }
            return false
        })
        XCTAssertTrue(plan.operations.contains {
            if case .schedule(_, let date) = $0 { return date == Date(timeIntervalSince1970: 2000) }
            return false
        })
    }
}

private actor ElevenLabsTransportStub: ProviderTransport {
    let status: Int
    let body: String
    private var received: [URLRequest] = []

    init(status: Int, body: String) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        received.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                                httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { received }
}
