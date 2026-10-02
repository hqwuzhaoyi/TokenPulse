import Foundation
import CoreFoundation

extension ProviderRegion {
    var alibabaOrigin: String {
        self == .china ? "https://bailian.console.aliyun.com" : "https://modelstudio.console.alibabacloud.com"
    }
    var alibabaRegionID: String { self == .china ? "cn-beijing" : "ap-southeast-1" }
    var alibabaCommodity: String { self == .china ? "sfm_codingplan_public_cn" : "sfm_codingplan_public_intl" }
    var alibabaPage: String {
        "\(alibabaOrigin)/\(alibabaRegionID)/?tab=\(self == .china ? "model" : "coding-plan")#/efm/coding_plan"
    }
    var alibabaEndpoint: URL {
        var components = URLComponents(string: alibabaOrigin)!
        components.path = "/data/api.json"
        components.queryItems = [
            .init(name: "action", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
            .init(name: "product", value: "broadscope-bailian"),
            .init(name: "api", value: "queryCodingPlanInstanceInfoV2"),
            .init(name: "currentRegionId", value: alibabaRegionID)
        ]
        return components.url!
    }
}

struct AlibabaCodingPlanProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .alibabaCodingPlan, credential.kind == .apiKey,
              let region = credential.providerRegion else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: region.alibabaEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONEncoder().encode([
            "queryCodingPlanInstanceInfoRequest": ["commodityCode": region.alibabaCommodity]
        ])
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.accessToken, forHTTPHeaderField: "x-api-key")
        request.setValue(credential.accessToken, forHTTPHeaderField: "X-DashScope-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(region.alibabaOrigin, forHTTPHeaderField: "Origin")
        request.setValue(region.alibabaPage, forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if [200, 401, 403].contains(response.statusCode),
               let object = try? ProviderHTTP.json(data), Self.needsConsoleSession(object) {
                throw RefreshFailure.consoleSessionRequired
            }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.regionalIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        var frame = try ProviderHTTP.json(data)
        // Only named envelope paths are unwrapped. Never search other objects
        // or expired instances for a usable-looking quota.
        for depth in 0...4 {
            try validateEnvelope(frame)
            if frame["codingPlanInstanceInfos"] != nil { break }
            guard let nested = frame["data"] ?? frame["result"] else { break }
            guard depth < 4 else { throw RefreshFailure.unreadableResponse }
            if let object = nested as? [String: Any] { frame = object }
            else if let text = nested as? String { frame = try ProviderHTTP.json(Data(text.utf8)) }
            else { throw RefreshFailure.unreadableResponse }
        }
        guard let plans = frame["codingPlanInstanceInfos"] as? [[String: Any]] else { throw RefreshFailure.noQuotaWindows }
        guard !plans.isEmpty else { throw RefreshFailure.subscriptionRequired }
        let active = plans.first { activity($0, now: collectedAt) == 2 }
            ?? plans.first { activity($0, now: collectedAt) == 1 }
        guard let active else {
            if plans.allSatisfy({ activity($0, now: collectedAt) == -1 }) { throw RefreshFailure.subscriptionRequired }
            throw RefreshFailure.noQuotaWindows
        }
        guard let quota = active["codingPlanQuotaInfo"] as? [String: Any] else { throw RefreshFailure.noQuotaWindows }
        let definitions: [(String, String, QuotaPeriod, [String], [String], [String])] = [
            ("fiveHour", "5 小时额度", .fiveHour, ["per5HourUsedQuota", "perFiveHourUsedQuota"], ["per5HourTotalQuota", "perFiveHourTotalQuota"], ["per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime"]),
            ("weekly", "每周额度", .weekly, ["perWeekUsedQuota"], ["perWeekTotalQuota"], ["perWeekQuotaNextRefreshTime"]),
            ("monthly", "账期额度", .monthly, ["perBillMonthUsedQuota", "perMonthUsedQuota"], ["perBillMonthTotalQuota", "perMonthTotalQuota"], ["perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime"])
        ]
        let windows = definitions.compactMap { id, name, period, usedKeys, totalKeys, resetKeys -> QuotaWindow? in
            guard let used = firstNumber(usedKeys, in: quota), used >= 0,
                  let total = firstNumber(totalKeys, in: quota), total > 0 else { return nil }
            let percentage = used / total * 100
            guard percentage.isFinite else { return nil }
            let reset = firstNumber(resetKeys, in: quota).flatMap(millisecondsDate).flatMap { $0 > collectedAt ? $0 : nil }
            return .init(id: "alibabaCodingPlan.\(id)", name: name, scope: nil, period: period,
                         isExhausted: used >= total, usedPercentage: percentage,
                         remainingCount: max(total - used, 0), totalCount: total, resetsAt: reset, unit: "次")
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        let name = ["planName", "instanceName", "packageName"].compactMap { active[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: name)
    }

    private static func validateEnvelope(_ frame: [String: Any]) throws {
        if needsConsoleSession(frame) { throw RefreshFailure.consoleSessionRequired }
        for key in ["statusCode", "status_code", "code"] where frame[key] != nil {
            guard let code = number(frame[key]), let integer = Int(exactly: code) else { throw RefreshFailure.unreadableResponse }
            switch integer {
            case 0, 200: break
            case 401, 403: throw RefreshFailure.invalidCredential
            case 429: throw RefreshFailure.rateLimited
            default: throw RefreshFailure.server
            }
        }
        for key in ["successResponse", "success", "Success"] where frame[key] != nil {
            guard let value = boolean(frame[key]) else { throw RefreshFailure.unreadableResponse }
            if !value { throw RefreshFailure.server }
        }
    }

    private static func needsConsoleSession(_ frame: [String: Any]) -> Bool {
        ["code", "errorCode", "status"].contains { (frame[$0] as? String)?.lowercased() == "consoleneedlogin" }
    }

    /// Explicit lapsed state or a past end wins over an inconsistent ACTIVE label.
    private static func activity(_ plan: [String: Any], now: Date) -> Int {
        let status = (plan["status"] ?? plan["instanceStatus"]) as? String
        if let status, ["EXPIRED", "INVALID", "INACTIVE", "DISABLED", "TERMINATED", "STOPPED"].contains(status.uppercased()) { return -1 }
        let active = boolean(plan["isActive"] ?? plan["active"])
        if active == false { return -1 }
        let end = ["endTime", "periodEndTime", "expireTime", "expirationTime"].compactMap { endDate(plan[$0]) }.first
        if let end, end <= now { return -1 }
        if active == true || status.map({ ["VALID", "ACTIVE"].contains($0.uppercased()) }) == true { return 2 }
        return end.map { $0 > now ? 1 : -1 } ?? 0
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        guard let number = ProviderHTTP.number(value), number.isFinite else { return nil }
        return number
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func firstNumber(_ keys: [String], in object: [String: Any]) -> Double? {
        keys.compactMap { number(object[$0]) }.first
    }
    private static func millisecondsDate(_ value: Double) -> Date? {
        guard value > 0, Int64(exactly: value.rounded()) != nil else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
    private static func endDate(_ value: Any?) -> Date? {
        if let value = number(value) { return millisecondsDate(value >= 1_000_000_000_000 ? value : value * 1000) }
        if let iso = ProviderHTTP.isoDate(value) { return iso }
        guard let text = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text), formatter.string(from: date) == text { return date }
        }
        return nil
    }
}
