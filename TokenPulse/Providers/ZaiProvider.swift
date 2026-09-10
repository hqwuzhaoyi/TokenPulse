import Foundation

struct ZaiProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            if root["success"] as? Bool != true || Int(ProviderHTTP.number(root["code"]) ?? 0) != 200 {
                switch Int(ProviderHTTP.number(root["code"]) ?? 0) {
                case 401, 403: throw RefreshFailure.invalidCredential
                case 429: throw RefreshFailure.rateLimited
                default: throw RefreshFailure.server
                }
            }
            let payload = root["data"] as? [String: Any]
            let windows = Self.windows(payload?["limits"] as? [[String: Any]] ?? [])
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(
                snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func windows(_ limits: [[String: Any]]) -> [QuotaWindow] {
        limits.enumerated().compactMap { index, limit in
            guard let type = limit["type"] as? String,
                  ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type),
                  let unit = ProviderHTTP.number(limit["unit"]).map(Int.init),
                  let count = ProviderHTTP.number(limit["number"]).map(Int.init),
                  let seconds = windowSeconds(type: type, unit: unit, count: count) else { return nil }
            let total = ProviderHTTP.number(limit["usage"])
            let remaining = ProviderHTTP.number(limit["remaining"])
            let current = ProviderHTTP.number(limit["currentValue"] ?? limit["current_value"])
            let percentage = ProviderHTTP.number(limit["percentage"])
            let usedPercentage: Double?
            if let total, total > 0, let used = current ?? remaining.map({ total - $0 }) {
                usedPercentage = min(max(used / total * 100, 0), 100)
            } else {
                usedPercentage = percentage.map { min(max($0, 0), 100) }
            }
            let resetValue = limit["nextResetTime"] ?? limit["next_reset_time"]
            let resetsAt = ProviderHTTP.number(resetValue).map { Date(timeIntervalSince1970: $0 / 1000) }
            let id = "zai.\(type).\(unit)-\(count).\(index)"
            return QuotaWindow(
                id: id,
                name: ProviderHTTP.windowName(seconds: seconds),
                scope: type == "TIME_LIMIT" ? "MCP" : nil,
                period: QuotaPeriod(seconds: seconds),
                usedPercentage: usedPercentage,
                remainingCount: remaining,
                totalCount: total,
                resetsAt: resetsAt
            )
        }.sorted { lhs, rhs in
            (lhs.resetsAt ?? .distantFuture) < (rhs.resetsAt ?? .distantFuture)
        }
    }

    private static func windowSeconds(type: String, unit: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        if type == "TIME_LIMIT", unit == 5, count == 1 { return 30 * 86_400 }
        let secondsPerUnit = [1: 86_400, 3: 3_600, 5: 60, 6: 7 * 86_400]
        return secondsPerUnit[unit].map { $0 * count }
    }
}
