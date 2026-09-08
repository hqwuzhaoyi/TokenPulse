import Foundation
import XCTest
@testable import TokenPulse

final class MiniMaxQuotaClientTests: XCTestCase {
    func testDecodesSeparateWindowsAndInvertsRemainingPercentage() throws {
        let accountID = UUID()
        let collectedAt = Date(timeIntervalSince1970: 500)
        let data = Data(#"""
        {
          "base_resp": { "status_code": 0 },
          "data": {
            "model_remains": [{
              "model_name": "general",
              "current_interval_status": 1,
              "current_interval_remaining_percent": "96",
              "current_interval_total_count": 1000,
              "current_interval_usage_count": "960",
              "start_time": 1760000000000,
              "end_time": 1760018000000,
              "current_weekly_status": 1,
              "current_weekly_remaining_percent": 75,
              "current_weekly_total_count": "4000",
              "current_weekly_usage_count": 3000,
              "weekly_end_time": 1760600000000
            }]
          }
        }
        """#.utf8)

        let result = try MiniMaxQuotaClient.decode(data, accountID: accountID, collectedAt: collectedAt)

        XCTAssertEqual(result.accountID, accountID)
        XCTAssertEqual(result.collectedAt, collectedAt)
        XCTAssertEqual(result.windows.map(\.name), ["5 小时额度", "每周额度"])
        XCTAssertEqual(result.windows[0].usedPercentage, 4)
        XCTAssertEqual(result.windows[0].remainingCount, 960)
        XCTAssertEqual(result.windows[1].usedPercentage, 25)
    }

    func testKeepsMissingMetricsMissingInsteadOfInventingValues() throws {
        let data = Data(#"""
        {
          "base_resp": { "status_code": 0 },
          "model_remains": [{
            "model_name": "text-model",
            "current_weekly_status": 1
          }]
        }
        """#.utf8)

        let result = try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date())

        XCTAssertEqual(result.windows.count, 1)
        XCTAssertNil(result.windows[0].usedPercentage)
        XCTAssertNil(result.windows[0].remainingCount)
        XCTAssertNil(result.windows[0].totalCount)
        XCTAssertNil(result.windows[0].resetsAt)
        XCTAssertEqual(QuotaFormatting.percentage(result.windows[0].usedPercentage), "未提供")
        XCTAssertEqual(QuotaFormatting.count(result.windows[0].remainingCount), "未提供")
    }

    func testDoesNotInventWeeklyWindowWhenResponseOnlyContainsInterval() throws {
        let data = Data(#"""
        {
          "base_resp": { "status_code": 0 },
          "model_remains": [{
            "model_name": "general",
            "current_interval_status": 1,
            "current_interval_remaining_percent": 50,
            "start_time": 1760000000000,
            "end_time": 1760018000000
          }]
        }
        """#.utf8)

        let result = try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date())

        XCTAssertEqual(result.windows.map(\.name), ["5 小时额度"])
    }

    func testKeepsIntervalMetricsWhenTimingIsMissing() throws {
        let data = Data(#"""
        {
          "base_resp": { "status_code": 0 },
          "model_remains": [{
            "model_name": "general",
            "current_interval_status": 1,
            "current_interval_remaining_percent": 40,
            "current_interval_total_count": 1000,
            "current_interval_usage_count": 400
          }]
        }
        """#.utf8)

        let result = try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date())

        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].name, "短周期额度")
        XCTAssertEqual(result.windows[0].usedPercentage, 60)
        XCTAssertEqual(result.windows[0].remainingCount, 400)
        XCTAssertNil(result.windows[0].resetsAt)
    }

    func testDecodesExplicitRemainingTimesRelativeToCollectionTime() throws {
        let collectedAt = Date(timeIntervalSince1970: 1_000)
        let data = Data(#"""
        {
          "base_resp": { "status_code": 0 },
          "model_remains": [{
            "model_name": "general",
            "remains_time": "3600000",
            "weekly_remains_time": 86400000
          }]
        }
        """#.utf8)

        let result = try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: collectedAt)

        let interval = try XCTUnwrap(result.windows.first(where: { $0.id.hasSuffix(".interval") }))
        let weekly = try XCTUnwrap(result.windows.first(where: { $0.id.hasSuffix(".weekly") }))
        XCTAssertEqual(interval.name, "短周期额度")
        XCTAssertEqual(interval.resetsAt, collectedAt.addingTimeInterval(3_600))
        XCTAssertEqual(weekly.resetsAt, collectedAt.addingTimeInterval(86_400))
    }

    func testRefreshFailureMessageOnlyClaimsOldDataWasKeptWhenSnapshotExists() {
        XCTAssertEqual(
            QuotaFormatting.refreshFailure(.network, hasSnapshot: false),
            "刷新失败：网络连接失败。"
        )
        XCTAssertEqual(
            QuotaFormatting.refreshFailure(.network, hasSnapshot: true),
            "刷新失败：网络连接失败。已保留上次成功数据。"
        )
    }

    func testUsesOnlyCurrentCodingPlanEndpointAndBearerAuthorization() async throws {
        let transport = TransportStub(result: .response(status: 200, data: Self.successResponse))
        let client = MiniMaxQuotaClient(transport: transport, now: { Date(timeIntervalSince1970: 123) })

        _ = try await client.quota(for: UUID(), credential: "placeholder-key")

        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.minimaxi.com/v1/token_plan/remains")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer placeholder-key")
        XCTAssertEqual(requests[0].httpMethod, "GET")
    }

    func testMapsHTTPErrorsWithoutMakingFallbackRequest() async {
        let cases: [(Int, RefreshFailure)] = [
            (401, .invalidCredential),
            (403, .invalidCredential),
            (404, .server),
            (429, .rateLimited),
            (500, .server),
        ]

        for (status, expected) in cases {
            let transport = TransportStub(result: .response(status: status, data: Data()))
            let client = MiniMaxQuotaClient(transport: transport)

            do {
                _ = try await client.quota(for: UUID(), credential: "placeholder-key")
                XCTFail("Expected HTTP \(status) to fail")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
            let requestCount = await transport.requestCount()
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testPropagatesCancellation() async {
        let transport = TransportStub(result: .cancelled)
        let client = MiniMaxQuotaClient(transport: transport)

        do {
            _ = try await client.quota(for: UUID(), credential: "placeholder-key")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testNormalizesURLSessionCancellation() async {
        let transport = TransportStub(result: .urlCancelled)
        let client = MiniMaxQuotaClient(transport: transport)

        do {
            _ = try await client.quota(for: UUID(), credential: "placeholder-key")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testMapsOnlyConfirmedCredentialBusinessCodes() {
        for code in [1004, 2049] {
            let data = Data("{\"base_resp\":{\"status_code\":\(code),\"status_msg\":\"opaque\"}}".utf8)
            XCTAssertThrowsError(try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .invalidCredential)
            }
        }

        for code in [1002, 2045] {
            let data = Data("{\"base_resp\":{\"status_code\":\(code),\"status_msg\":\"invalid token\"}}".utf8)
            XCTAssertThrowsError(try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .rateLimited)
            }
        }

        let unknown = Data("{\"base_resp\":{\"status_code\":9999,\"status_msg\":\"invalid token\"}}".utf8)
        XCTAssertThrowsError(try MiniMaxQuotaClient.decode(unknown, accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .server)
        }
    }

    func testWeeklyUnlimitedIsKeptUnlessBothModelWindowsAreUnallocated() throws {
        let data = Data(#"""
        {
          "base_resp": { "status_code": 0 },
          "model_remains": [
            {
              "model_name": "general",
              "current_interval_status": 1,
              "current_interval_total_count": 100,
              "current_interval_remaining_percent": 50,
              "start_time": 1760000000000,
              "end_time": 1760018000000,
              "current_weekly_status": 3,
              "current_weekly_total_count": 0,
              "current_weekly_usage_count": 0
            },
            {
              "model_name": "video",
              "current_interval_status": 3,
              "current_interval_total_count": 0,
              "current_weekly_status": 3,
              "current_weekly_total_count": 0
            }
          ]
        }
        """#.utf8)

        let result = try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date())

        XCTAssertEqual(result.windows.count, 2)
        XCTAssertFalse(result.windows[0].isUnlimited)
        let weekly = try XCTUnwrap(result.windows.first(where: { $0.id == "general.weekly" }))
        XCTAssertTrue(weekly.isUnlimited)
        XCTAssertEqual(QuotaFormatting.limitDescription(weekly), "无限")
        XCTAssertFalse(result.windows.contains(where: { $0.id.hasPrefix("video.") }))
    }

    private static let successResponse = Data(#"""
    {
      "base_resp": { "status_code": 0 },
      "model_remains": [{
        "model_name": "general",
        "current_weekly_status": 1,
        "current_weekly_remaining_percent": 75
      }]
    }
    """#.utf8)
}

private actor TransportStub: HTTPTransport {
    enum Result: Sendable {
        case response(status: Int, data: Data)
        case cancelled
        case urlCancelled
    }

    private let result: Result
    private var receivedRequests: [URLRequest] = []

    init(result: Result) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        switch result {
        case let .response(status, data):
            return (
                data,
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        case .cancelled:
            throw CancellationError()
        case .urlCancelled:
            throw URLError(.cancelled)
        }
    }

    func requests() -> [URLRequest] { receivedRequests }
    func requestCount() -> Int { receivedRequests.count }
}
