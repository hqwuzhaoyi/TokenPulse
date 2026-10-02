import Foundation
import CoreFoundation

struct ZaiProviderClient: Sendable {
    let provider: Provider
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard [.zai, .zhipu].contains(provider), credential.provider == provider,
              credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        let host = provider == .zhipu ? "https://open.bigmodel.cn" : "https://api.z.ai"
        var request = URLRequest(url: URL(string: "\(host)/api/monitor/usage/quota/limit")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            if root["success"] as? Bool != true || Self.number(root["code"]) != 200 {
                // A lapsed subscription can return generic code 500 with this
                // message. It is different from a refused Key on either host.
                if (root["msg"] as? String)?.lowercased().contains("coding plan") == true {
                    throw RefreshFailure.subscriptionRequired
                }
                switch Self.number(root["code"]) {
                case 401, 403, 1000, 1001: throw RefreshFailure.invalidCredential
                case 429: throw RefreshFailure.rateLimited
                default: throw RefreshFailure.server
                }
            }
            let payload = root["data"] as? [String: Any]
            let windows = Self.windows(payload?["limits"] as? [[String: Any]] ?? [], provider: provider)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(
                snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func windows(_ limits: [[String: Any]], provider: Provider = .zai) -> [QuotaWindow] {
        limits.enumerated().compactMap { index, limit in
            guard let type = limit["type"] as? String,
                  ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type),
                  let unit = integer(limit["unit"]),
                  let count = integer(limit["number"]),
                  let seconds = windowSeconds(type: type, unit: unit, count: count) else { return nil }
            let total = nonnegative(limit["usage"])
            let remaining = nonnegative(limit["remaining"])
            let current = nonnegative(limit["currentValue"] ?? limit["current_value"])
            let percentage = number(limit["percentage"])
            let usedPercentage: Double?
            if let total, total > 0, let used = current ?? remaining.map({ total - $0 }) {
                usedPercentage = min(max(used / total * 100, 0), 100)
            } else {
                usedPercentage = percentage.map { min(max($0, 0), 100) }
            }
            let resetValue = limit["nextResetTime"] ?? limit["next_reset_time"]
            let resetsAt = nonnegative(resetValue).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            let id = "\(provider.rawValue).\(type).\(unit)-\(count).\(index)"
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
        guard let multiplier = secondsPerUnit[unit] else { return nil }
        let product = multiplier.multipliedReportingOverflow(by: count)
        return product.overflow ? nil : product.partialValue
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        guard let number = ProviderHTTP.number(value), number.isFinite else { return nil }
        return number
    }

    private static func nonnegative(_ value: Any?) -> Double? {
        number(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value = number(value), value.rounded() == value else { return nil }
        return Int(exactly: value)
    }
}
