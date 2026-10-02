import CoreFoundation
import CryptoKit
import Foundation

enum StepFunSite: String, Codable, CaseIterable, Identifiable, Sendable {
    case china, international
    var id: String { rawValue }
    var host: String { self == .china ? "platform.stepfun.com" : "platform.stepfun.ai" }
    var cookieDomain: String { self == .china ? "stepfun.com" : "stepfun.ai" }
    var displayName: String { self == .china ? "国内站 · stepfun.com" : "国际站 · stepfun.ai" }
    var origin: String { "https://\(host)" }
    var usageURL: URL { URL(string: "\(origin)/plan-usage")! }
    func endpoint(_ method: String) -> URL {
        URL(string: "\(origin)/api/step.openapi.devcenter.Dashboard/\(method)")!
    }
}

/// The allowlist is pinned to Pulse 397c8fc4. Device IDs are replayed, never generated.
enum StepFunSession {
    static let cookieNames = ["Oasis-Token", "Oasis-Webid", "INGRESSCOOKIE"]

    static func fingerprint(_ encoded: String) -> String? {
        guard let credential = try? ProviderCredentialEnvelope.decode(encoded, expectedProvider: .stepFun),
              let site = credential.metadata["site"] else { return nil }
        return SHA256.hash(data: Data("\(site)\n\(credential.accessToken)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func values(in header: String) throws -> [String: String] {
        guard header.utf8.count <= 32_768,
              header.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value <= 126 }) else {
            throw RefreshFailure.invalidCredential
        }
        var values: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw RefreshFailure.invalidCredential }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard cookieNames.contains(name), !value.isEmpty,
                  !value.contains("\""), !value.contains("\\"), !value.contains(" "),
                  values[name] == nil else { throw RefreshFailure.invalidCredential }
            values[name] = value
        }
        guard values["Oasis-Token"] != nil else { throw RefreshFailure.invalidCredential }
        return values
    }

    static func webID(_ values: [String: String]) throws -> String {
        let claims = (values["Oasis-Token"] ?? "").components(separatedBy: "...").compactMap { token -> String? in
            let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count == 3 else { return nil }
            var payload = pieces[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return root["device_id"] as? String
        }
        let candidates = Set(claims + [values["Oasis-Webid"]].compactMap { $0 })
        guard candidates.count == 1, let id = candidates.first, !id.isEmpty, id.utf8.count <= 1024,
              id.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
              !id.contains(";"), !id.contains("\""), !id.contains("\\") else {
            throw RefreshFailure.invalidCredential
        }
        return id
    }

    static func credential(cookies: [HTTPCookie], site: StepFunSite, accountID: UUID, now: Date) throws -> String {
        let selection = try WebSessionCookiePolicy.select(cookies, names: cookieNames, requiredNames: ["Oasis-Token"],
                                                         domains: [site.host, site.cookieDomain],
                                                         path: site.endpoint("QueryStepPlanRateLimit").path, now: now)
        let header = selection.header
        let checked = try self.values(in: header)
        let webID = try webID(checked)
        var credential = ProviderCredentialEnvelope(provider: .stepFun, kind: .session, accessToken: header,
                                               expiresAt: selection.expiresByName["Oasis-Token"],
                                               metadata: ["site": site.rawValue, "host": site.host,
                                                          "webID": webID, "cookieFormat": "restrictedHeader",
                                                          "localAccountID": accountID.uuidString])
        credential.metadata["sourceCredentialFingerprint"] = try fingerprint(credential.encoded())
        return try credential.encoded()
    }

    static func validate(_ credential: ProviderCredentialEnvelope, accountID: UUID, now: Date) throws -> StepFunSite {
        guard credential.provider == .stepFun, credential.kind == .session,
              let site = credential.metadata["site"].flatMap(StepFunSite.init(rawValue:)),
              credential.metadata["host"] == site.host,
              credential.metadata["cookieFormat"] == "restrictedHeader",
              try fingerprint(credential.encoded()) == credential.metadata["sourceCredentialFingerprint"],
              credential.metadata["localAccountID"] == accountID.uuidString,
              credential.expiresAt.map({ $0 > now }) != false,
              try webID(values(in: credential.accessToken)) == credential.metadata["webID"] else {
            throw RefreshFailure.invalidCredential
        }
        return site
    }
}

struct StepFunProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        let date = now()
        let site = try StepFunSession.validate(credential, accountID: accountID, now: date)
        var request = URLRequest(url: site.endpoint("QueryStepPlanRateLimit"))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        for (name, value) in ["Cookie": credential.accessToken, "Content-Type": "application/json",
                              "Accept": "application/json", "Origin": site.origin,
                              "Referer": site.usageURL.absoluteString, "oasis-appid": "10300",
                              "oasis-platform": "web", "oasis-webid": credential.metadata["webID"]!,
                              "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let windows = try Self.windows(ProviderHTTP.json(data), now: date)
            // An authenticated no-plan answer is fresh empty data: it clears a banked old plan.
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: date,
                                                 sourceCredentialFingerprint: Self.fingerprint(credential)),
                         updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private static func fingerprint(_ credential: ProviderCredentialEnvelope) -> String? {
        (try? credential.encoded()).flatMap(StepFunSession.fingerprint)
    }

    static func windows(_ root: [String: Any], now: Date) throws -> [QuotaWindow] {
        guard number(root["status"]) == 1 else {
            let message = [root["desc"], root["message"], root["code"]].compactMap { $0 as? String }
                .joined(separator: " ").lowercased()
            throw message.contains("auth") || message.contains("token")
                ? RefreshFailure.invalidCredential : RefreshFailure.unreadableResponse
        }
        let coding = [("five_hour", "stepfun.5h", QuotaPeriod.fiveHour, "5 小时额度"),
                      ("weekly", "stepfun.weekly", .weekly, "每周额度")].compactMap { key, id, period, name -> QuotaWindow? in
            guard let reset = timestamp(root["\(key)_usage_reset_time"]),
                  let left = fraction(root["\(key)_usage_left_rate"]) else { return nil }
            return QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: left == 0,
                               usedPercentage: (1 - left) * 100, remainingCount: nil, totalCount: nil, resetsAt: reset)
        }
        if !coding.isEmpty { return coding }
        if ["five_hour_usage_reset_time", "weekly_usage_reset_time"].contains(where: { timestamp(root[$0]) != nil }) {
            throw RefreshFailure.unreadableResponse
        }
        guard let credit = root["plan_credit_rate_limit"] as? [String: Any] else { return [] }
        if let entries = credit["credit_buckets"] as? [[String: Any]], !entries.isEmpty {
            // Never silently discard an invalid bucket and present a partial aggregate as the whole pool.
            let buckets = try entries.map { entry -> (Double, Double, Date?, Date?) in
                guard let total = number(entry["credit_total"]), total > 0,
                      let residual = number(entry["credit_residual"]), residual >= 0, residual <= total else {
                    throw RefreshFailure.unreadableResponse
                }
                return (total, residual, timestamp(entry["expire_at"]), timestamp(entry["next_reset_at"]))
            }
            let total = buckets.reduce(0) { $0 + $1.0 }
            let remaining = buckets.reduce(0) { $0 + $1.1 }
            guard total.isFinite, remaining.isFinite else { throw RefreshFailure.unreadableResponse }
            return [QuotaWindow(id: "stepfun.credits", name: "Token Plan 积分额度", scope: nil, period: .other,
                                isExhausted: remaining == 0, usedPercentage: (total - remaining) / total * 100,
                                remainingCount: remaining, totalCount: total,
                                resetsAt: buckets.compactMap { $0.3 }.filter { $0 > now }.min(), unit: "积分",
                                expiresAt: buckets.filter { $0.1 > 0 }.compactMap { $0.2 }.filter { $0 > now }.min())]
        }
        // A zero fraction without buckets is ambiguous (also sent for a plan the account does not have).
        let subscription = fraction(credit["subscription_credit_left_rate"]).flatMap { $0 > 0 ? $0 : nil }
        let topUp = fraction(credit["topup_credit_left_rate"]).flatMap { $0 > 0 ? $0 : nil }
        guard let left = subscription ?? topUp else { return [] }
        return [QuotaWindow(id: "stepfun.credits", name: "Token Plan 积分额度", scope: nil, period: .other,
                            usedPercentage: (1 - left) * 100, remainingCount: nil, totalCount: nil,
                            resetsAt: nil, unit: "积分")]
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value, CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID(),
              let number = ProviderHTTP.number(value), number.isFinite else { return nil }
        return number
    }
    private static func fraction(_ value: Any?) -> Double? {
        number(value).flatMap { 0...1 ~= $0 ? $0 : nil }
    }
    static func timestamp(_ value: Any?) -> Date? {
        number(value).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) : nil }
    }
}
