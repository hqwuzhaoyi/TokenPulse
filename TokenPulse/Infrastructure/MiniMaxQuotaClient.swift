import Foundation
import CoreFoundation

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

    static func decode(_ data: Data, accountID: UUID, collectedAt: Date,
                       discardUnallocatedPools: Bool = false) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RefreshFailure.unreadableResponse
        }

        if let baseResponse = root["base_resp"] as? [String: Any] {
            guard let status = number(baseResponse["status_code"]) else { throw RefreshFailure.unreadableResponse }
            if status != 0 {
                switch status {
                case 1002, 2045:
                    throw RefreshFailure.rateLimited
                case 1004, 2049:
                    throw RefreshFailure.invalidCredential
                default:
                    throw RefreshFailure.server
                }
            }
        }

        let payload = (root["data"] as? [String: Any]) ?? root
        let models = payload["model_remains"] as? [[String: Any]] ?? []
        let parsedWindows = models.enumerated().flatMap { index, model in
            Self.windows(from: model, index: index, collectedAt: collectedAt,
                         discardUnallocatedPools: discardUnallocatedPools)
        }.sorted { $0.name < $1.name }

        guard !parsedWindows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: parsedWindows, collectedAt: collectedAt)
    }

    private static func windows(from model: [String: Any], index: Int, collectedAt: Date,
                                discardUnallocatedPools: Bool) -> [QuotaWindow] {
        let rawScope = (model["model_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = rawScope?.lowercased() == "general" || rawScope?.isEmpty == true ? nil : rawScope
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
        if modelHasNoQuota && !discardUnallocatedPools { return [] }

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
        let intervalUnallocated = intervalStatus == 3 && intervalTotal == 0 && intervalRemainingPercent == 100
        if hasIntervalWindow && !(discardUnallocatedPools && intervalUnallocated) {
            let remaining = number(model["current_interval_usage_count"])
            let start = millisecondsDate(model["start_time"])
            let end = millisecondsDate(model["end_time"])
            let duration = start.flatMap { start in end.map { $0.timeIntervalSince(start).rounded() } }
            let hasValidTiming = duration.map { $0 >= 1 && $0 < Double(Int.max) } == true
            let resetsAt: Date?
            let name: String
            let period: QuotaPeriod
            if let start, let end, hasValidTiming {
                let seconds = Int(end.timeIntervalSince(start).rounded())
                name = "\(max(seconds / 3_600, 1)) 小时额度"
                period = QuotaPeriod(seconds: seconds)
                resetsAt = end
            } else {
                name = "短周期额度"
                period = .other
                resetsAt = remainingTimeDate(model["remains_time"], collectedAt: collectedAt)
            }
            result.append(QuotaWindow(
                id: "\(lane).interval",
                name: name,
                scope: scope,
                period: period,
                isUnlimited: intervalUnlimited,
                usedPercentage: intervalUnlimited ? nil : usedPercentage(
                    remainingPercent: intervalRemainingPercent,
                    total: intervalTotal,
                    remaining: remaining
                ),
                remainingCount: remaining,
                totalCount: intervalTotal,
                resetsAt: resetsAt
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
        let weeklyUnallocated = weeklyStatus == 3 && weeklyTotal == 0 && weeklyRemainingPercent == 100
        if hasWeeklyWindow && !(discardUnallocatedPools && weeklyUnallocated) {
            let remaining = number(model["current_weekly_usage_count"])
            result.append(QuotaWindow(
                id: "\(lane).weekly",
                name: "每周额度",
                scope: scope,
                period: .weekly,
                isUnlimited: weeklyUnlimited,
                usedPercentage: weeklyUnlimited ? nil : usedPercentage(
                    remainingPercent: weeklyRemainingPercent,
                    total: weeklyTotal,
                    remaining: remaining
                ),
                remainingCount: remaining,
                totalCount: weeklyTotal,
                resetsAt: millisecondsDate(model["weekly_end_time"])
                    ?? remainingTimeDate(model["weekly_remains_time"], collectedAt: collectedAt)
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
        number(value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
    }

    private static func remainingTimeDate(_ value: Any?, collectedAt: Date) -> Date? {
        guard let milliseconds = number(value), milliseconds.isFinite, milliseconds >= 0 else { return nil }
        return collectedAt.addingTimeInterval(milliseconds / 1000)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
            return number.doubleValue
        }
        if let text = value as? String {
            guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { return nil }
            return number
        }
        return nil
    }
}

/// International accounts always use their own host and a provider-bound Key.
/// Mainland legacy raw Key storage and query behavior remain compatible.
struct MiniMaxInternationalProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .miniMaxInternational, credential.kind == .apiKey else {
            throw RefreshFailure.invalidCredential
        }
        do {
            let current = try await request(path: "/v1/token_plan/remains", credential: credential)
            // The documented compatibility condition is a missing current
            // route. Other failures must not be masked by a second request.
            let result = current.1.statusCode == 404
                ? try await request(path: "/v1/api/openplatform/coding_plan/remains", credential: credential)
                : current
            if let failure = ProviderHTTP.queryFailure(status: result.1.statusCode) { throw failure }
            let snapshot = try MiniMaxQuotaClient.decode(result.0, accountID: accountID, collectedAt: now(),
                                                        discardUnallocatedPools: true)
            return ProviderQueryResult(snapshot: snapshot, updatedCredential: nil)
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    private func request(path: String, credential: ProviderCredentialEnvelope) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://api.minimax.io\(path)")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await ProviderHTTP.send(request, transport: transport)
    }
}
