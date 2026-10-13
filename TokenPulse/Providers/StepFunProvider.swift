import CoreFoundation
import CryptoKit
import Foundation

enum StepFunSite: String, Codable, CaseIterable, Identifiable, Sendable {
    case china, international
    var id: String { rawValue }
    var host: String { self == .china ? "platform.stepfun.com" : "platform.stepfun.ai" }
    var cookieDomain: String { self == .china ? "stepfun.com" : "stepfun.ai" }
    var displayName: String { self == .china ? L10n.text("国内站 · stepfun.com") : L10n.text("国际站 · stepfun.ai") }
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
        let lanes = [("five_hour", "stepfun.5h", QuotaPeriod.fiveHour, "5 小时额度"),
                     ("weekly", "stepfun.weekly", .weekly, "每周额度")]
        var coding: [QuotaWindow] = []
        var zeroedCoding = true
        for (key, id, period, name) in lanes {
            let left = try statedFraction(root["\(key)_usage_left_rate"])
            let reset = try statedTimestamp(root["\(key)_usage_reset_time"])
            if let reset {
                guard let left else { throw RefreshFailure.unreadableResponse }
                coding.append(QuotaWindow(id: id, name: name, scope: nil, period: period,
                                          isExhausted: left == 0, usedPercentage: (1 - left) * 100,
                                          remainingCount: nil, totalCount: nil, resetsAt: reset))
            }
            // A missing lane is not a confirmed absent lane. The pinned no-plan fixture explicitly zeroes both.
            zeroedCoding = zeroedCoding && left == 0 && number(root["\(key)_usage_reset_time"]) == 0
        }
        let credit: [String: Any]?
        if let stated = root["plan_credit_rate_limit"] {
            guard let dictionary = stated as? [String: Any] else { throw RefreshFailure.unreadableResponse }
            credit = dictionary
        } else { credit = nil }
        let subscription = try statedFraction(credit?["subscription_credit_left_rate"])
        let topUp = try statedFraction(credit?["topup_credit_left_rate"])
        let entries: [[String: Any]]?
        if let stated = credit?["credit_buckets"] {
            guard let list = stated as? [Any] else { throw RefreshFailure.unreadableResponse }
            entries = try list.map {
                guard let entry = $0 as? [String: Any] else { throw RefreshFailure.unreadableResponse }
                return entry
            }
        } else { entries = nil }
        // Validate explicit inactive-plan fields too; malformed data must not turn into a no-plan observation.
        let buckets = try (entries ?? []).map { entry -> (Double, Double, Date?, Date?) in
            guard let total = number(entry["credit_total"]), total > 0,
                  let residual = number(entry["credit_residual"]), residual >= 0, residual <= total else {
                throw RefreshFailure.unreadableResponse
            }
            return (total, residual, try statedTimestamp(entry["expire_at"]), try statedTimestamp(entry["next_reset_at"]))
        }
        if !coding.isEmpty { return coding }
        if !buckets.isEmpty {
            let total = buckets.reduce(0) { $0 + $1.0 }
            let remaining = buckets.reduce(0) { $0 + $1.1 }
            guard total.isFinite, remaining.isFinite else { throw RefreshFailure.unreadableResponse }
            return [QuotaWindow(id: "stepfun.credits", name: "Token Plan 积分额度", scope: nil, period: .other,
                                isExhausted: remaining == 0, usedPercentage: (total - remaining) / total * 100,
                                remainingCount: remaining, totalCount: total,
                                resetsAt: buckets.compactMap { $0.3 }.filter { $0 > now }.min(), unit: "积分",
                                expiresAt: buckets.filter { $0.1 > 0 }.compactMap { $0.2 }.filter { $0 > now }.min())]
        }
        // No sizes: prefer the subscription fraction, never add unlike pools.
        if let left = subscription.flatMap({ $0 > 0 ? $0 : nil }) ?? topUp.flatMap({ $0 > 0 ? $0 : nil }) {
            return [QuotaWindow(id: "stepfun.credits", name: "Token Plan 积分额度", scope: nil, period: .other,
                                usedPercentage: (1 - left) * 100, remainingCount: nil, totalCount: nil,
                                resetsAt: nil, unit: "积分")]
        }
        // Only the fully zeroed synthetic fixture in pinned StepFunParsingTests establishes this contract.
        guard zeroedCoding, subscription == 0, topUp == 0, entries?.isEmpty == true else {
            throw RefreshFailure.unreadableResponse
        }
        return []
    }

    private static func statedFraction(_ value: Any?) throws -> Double? {
        guard let value else { return nil }
        guard let number = fraction(value) else { throw RefreshFailure.unreadableResponse }
        return number
    }

    private static func statedTimestamp(_ value: Any?) throws -> Date? {
        guard let value else { return nil }
        guard let stamp = number(value), stamp >= 0 else { throw RefreshFailure.unreadableResponse }
        if stamp == 0 { return nil }
        guard let date = timestamp(stamp) else { throw RefreshFailure.unreadableResponse }
        return date
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
        guard let stamp = number(value), stamp > 0 else { return nil }
        let seconds = stamp > 10_000_000_000 ? stamp / 1000 : stamp
        guard seconds <= 253_402_300_799 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
