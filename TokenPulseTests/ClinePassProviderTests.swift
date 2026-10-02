import Foundation
import XCTest
@testable import TokenPulse

final class ClinePassProviderTests: XCTestCase {
    private let body = #"{"success":true,"data":{"limits":[{"type":"monthly","percentUsed":125},{"type":"five_hour","percentUsed":0,"resetsAt":"2026-10-03T10:00:00Z"},{"type":"weekly","percentUsed":0.5}]}}"#

    func testOrderedWindowsPreservePercentageScaleAndDoNotInventCountsOrResets() throws {
        let snapshot = try ClinePassProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.map(\.period), [.fiveHour, .weekly, .monthly])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [0, 0.5, 125])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.totalCount == nil && $0.remainingCount == nil && $0.wallet == nil })
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.windows[2].resetsAt)
    }

    func testUnknownMissingAndInvalidValuesDoNotBecomeZero() throws {
        let body = #"{"success":true,"data":{"limits":[{"type":"weekly"},{"type":"five_hour","percentUsed":-1},{"type":"future_type","percentUsed":0}]}}"#
        XCTAssertTrue(try ClinePassProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date()).windows.isEmpty)
        for body in [#"{"success":1,"data":{"limits":[]}}"#,
                     #"{"success":true,"data":{"limits":[{"type":"weekly","percentUsed":false}]}}"#,
                     #"{"success":true,"data":{"limits":[{"type":"weekly","percentUsed":1},{"type":"weekly","percentUsed":2}]}}"#,
                     #"{"success":true,"data":{}}"#] {
            XCTAssertThrowsError(try ClinePassProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date()))
        }
    }

    func testPublicClientUsesSelectedKeyAndMapsRefusalWithoutPublishingFalseQuota() async throws {
        let transport = ClinePassTransport(body: body)
        let client = ProviderQuotaClient(provider: .clinePass, transport: transport)
        let controller = ProviderAuthenticationController()
        for key in ["fixture-a", "fixture-b"] {
            let accountID = UUID()
            let credential = try controller.credential(provider: .clinePass, apiKey: key)
            let snapshot = try await client.quota(for: accountID, credential: credential)
            XCTAssertEqual(snapshot.accountID, accountID)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer fixture-a", "Bearer fixture-b"])
        XCTAssertTrue(requests.allSatisfy { $0.url?.absoluteString == "https://api.cline.bot/api/v1/users/me/plan/usage-limits" && $0.httpMethod == "GET" })
        for (status, failure) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            let failed = ProviderQuotaClient(provider: .clinePass, transport: ClinePassTransport(body: "{}", status: status))
            do {
                _ = try await failed.quota(for: UUID(), credential: controller.credential(provider: .clinePass, apiKey: "fixture"))
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? RefreshFailure, failure) }
        }
    }

    func testWidgetAndAlertUseOnlyReportedWindows() throws {
        let account = SubscriptionAccount(name: "ClinePass", provider: .clinePass)
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = try ClinePassProviderClient.snapshot(Data(body.utf8), accountID: account.id, collectedAt: now)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(widget.displayMetrics.map(\.window?.id), snapshot.windows.map { Optional($0.id) })
        let plan = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name,
            previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        XCTAssertTrue(plan.operations.contains {
            if case .deliver(let notification) = $0 { return notification.kind == .quotaAlert && notification.body.contains("每月") }
            return false
        })
        XCTAssertFalse(plan.operations.contains { if case .schedule = $0 { return true }; return false })
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }
}

private actor ClinePassTransport: ProviderTransport {
    let body: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(body: String, status: Int = 200) { self.body = body; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
