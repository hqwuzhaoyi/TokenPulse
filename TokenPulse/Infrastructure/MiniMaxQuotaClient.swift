import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

struct MiniMaxQuotaClient: QuotaQuerying {
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    init(transport: any HTTPTransport = URLSessionTransport(),
         now: @escaping @Sendable () -> Date = Date.init) {
        self.transport = transport
        self.now = now
    }

    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        var request = URLRequest(url: URL(string: "https://api.minimaxi.com/v1/token_plan/remains")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue {
                throw CancellationError()
            }
            throw RefreshFailure.network
        }

        guard let http = response as? HTTPURLResponse else { throw RefreshFailure.network }
        switch http.statusCode {
        case 200:
            return try Self.decode(data, accountID: accountID, collectedAt: now())
        case 401, 403:
            throw RefreshFailure.invalidCredential
        case 429:
            throw RefreshFailure.rateLimited
        default:
            throw RefreshFailure.server
        }
    }

    static func decode(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RefreshFailure.unreadableResponse
        }

        if let baseResponse = root["base_resp"] as? [String: Any],
           let status = number(baseResponse["status_code"]), status != 0 {
            switch status {
            case 1002, 2045:
                throw RefreshFailure.rateLimited
            case 1004, 2049:
                throw RefreshFailure.invalidCredential
            default:
                throw RefreshFailure.server
            }
        }

        let payload = (root["data"] as? [String: Any]) ?? root
        let models = payload["model_remains"] as? [[String: Any]] ?? []
        let parsedWindows = models.enumerated().flatMap { index, model in
            Self.windows(from: model, index: index, collectedAt: collectedAt)
        }.sorted { $0.name < $1.name }

        guard !parsedWindows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: parsedWindows, collectedAt: collectedAt)
    }

    private static func windows(from model: [String: Any], index: Int, collectedAt: Date) -> [QuotaWindow] {
        let rawScope = (model["model_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = rawScope?.lowercased() == "general" ? nil : rawScope
        let lane = (rawScope?.isEmpty == false ? rawScope! : "lane\(index)")
        var result: [QuotaWindow] = []

        let intervalStatus = number(model["current_interval_status"])
        let intervalTotal = number(model["current_interval_total_count"])
        let intervalRemainingPercent = number(model["current_interval_remaining_percent"])
        let weeklyStatus = number(model["current_weekly_status"])
        let weeklyTotal = number(model["current_weekly_total_count"])
        let weeklyRemainingPercent = number(model["current_weekly_remaining_percent"])
        let modelHasNoQuota = intervalStatus == 3
            && weeklyStatus == 3
            && intervalTotal == 0
            && weeklyTotal == 0
        if modelHasNoQuota { return [] }

        let hasIntervalWindow = [
            "current_interval_status",
            "current_interval_total_count",
            "current_interval_remaining_percent",
            "current_interval_usage_count",
            "start_time",
            "end_time",
            "remains_time",
        ].contains { model[$0] != nil }
        let intervalUnlimited = intervalStatus == 3
        if hasIntervalWindow {
            let remaining = number(model["current_interval_usage_count"])
            let start = millisecondsDate(model["start_time"])
            let end = millisecondsDate(model["end_time"])
            let hasValidTiming = start.flatMap { start in end.map { $0 > start } } == true
            let resetsAt: Date?
            let name: String
            if let start, let end, hasValidTiming {
                name = "\(max(Int(end.timeIntervalSince(start) / 3600), 1)) 小时额度"
                resetsAt = end
            } else {
                name = "短周期额度"
                resetsAt = remainingTimeDate(model["remains_time"], collectedAt: collectedAt)
            }
            result.append(QuotaWindow(
                id: "\(lane).interval",
                name: name,
                scope: scope,
                isUnlimited: intervalUnlimited,
                usedPercentage: intervalUnlimited ? nil : usedPercentage(
                    remainingPercent: intervalRemainingPercent,
                    total: intervalTotal,
                    remaining: remaining
                ),
                remainingCount: remaining,
                totalCount: intervalTotal,
                resetsAt: resetsAt,
                cycleID: start.map { "start:\($0.timeIntervalSince1970)" }
            ))
        }

        let hasWeeklyWindow = [
            "current_weekly_status",
            "current_weekly_total_count",
            "current_weekly_remaining_percent",
            "current_weekly_usage_count",
            "weekly_end_time",
            "weekly_remains_time",
        ].contains { model[$0] != nil }
        let weeklyUnlimited = weeklyStatus == 3
        if hasWeeklyWindow {
            let remaining = number(model["current_weekly_usage_count"])
            result.append(QuotaWindow(
                id: "\(lane).weekly",
                name: "每周额度",
                scope: scope,
                isUnlimited: weeklyUnlimited,
                usedPercentage: weeklyUnlimited ? nil : usedPercentage(
                    remainingPercent: weeklyRemainingPercent,
                    total: weeklyTotal,
                    remaining: remaining
                ),
                remainingCount: remaining,
                totalCount: weeklyTotal,
                resetsAt: millisecondsDate(model["weekly_end_time"])
                    ?? remainingTimeDate(model["weekly_remains_time"], collectedAt: collectedAt),
                cycleID: millisecondsDate(model["weekly_end_time"]).map { "end:\($0.timeIntervalSince1970)" }
            ))
        }

        return result
    }

    private static func usedPercentage(remainingPercent: Double?, total: Double?, remaining: Double?) -> Double? {
        if let remainingPercent { return min(max(100 - remainingPercent, 0), 100) }
        guard let total, total > 0, let remaining else { return nil }
        return min(max((total - remaining) / total * 100, 0), 100)
    }

    private static func millisecondsDate(_ value: Any?) -> Date? {
        number(value).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    private static func remainingTimeDate(_ value: Any?, collectedAt: Date) -> Date? {
        guard let milliseconds = number(value), milliseconds.isFinite, milliseconds >= 0 else { return nil }
        return collectedAt.addingTimeInterval(milliseconds / 1000)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
