import Foundation
import CryptoKit

/// Kiro's official web portal, not the desktop ACP process or a guessed AWS endpoint.
struct KiroProviderClient: Sendable {
    static let origin = "https://app.kiro.dev"
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["app.kiro.dev", "kiro.dev"], path: "/",
        includeAllNames: true, deniedPrefixes: ["_ga", "_gid", "_gat", "_fbp", "_clck", "_clsk", "amplitude", "mp_", "cwr-"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    static var loginProfile: WebProviderLoginProfile {
        WebProviderLoginProfile(loginURL: URL(string: origin)!, allowedOrigins: [origin], makeCredentials: { cookies, _, accountID, now in
            let selection = try cookiePolicy.select(cookies, now: now)
            let expiries = selection.expiresByName.mapValues { floor($0.timeIntervalSince1970) }
            let base = try WebProviderSession.credential(provider: .kiro, origin: origin, accountID: accountID,
                accessToken: selection.header, expiresAt: expiries.values.min().map(Date.init(timeIntervalSince1970:)),
                metadata: ["kiroCookieExpiries": try expiryJSON(expiries)])
            let client = Self(transport: URLSessionProviderTransport.rejectingRedirects(), now: { now })
            var jar = try Jar(credential: base)
            let identity = try await client.bootstrap(jar: &jar)
            let session = try WebProviderSession.credential(provider: .kiro, origin: origin, accountID: accountID,
                accessToken: jar.header, expiresAt: jar.expiresAt, remoteAccountID: identity.userID,
                metadata: ["kiroProfileArn": identity.profileArn, "kiroIdp": identity.idp, "kiroCookieExpiries": try expiryJSON(jar.expiries)])
            return [WebLoginCredentialChoice(id: identity.userID, title: "Kiro 订阅账号", credential: try session.encoded())]
        })
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try WebProviderSession.validate(credential, provider: .kiro, accountID: accountID, origins: [Self.origin], now: now())
            var jar = try Jar(credential: credential)
            let identity = try await bootstrap(jar: &jar)
            guard identity.userID == credential.accountID, identity.profileArn == credential.metadata["kiroProfileArn"],
                  identity.idp == credential.metadata["kiroIdp"] else { throw RefreshFailure.invalidCredential }
            var csrf = identity.csrf
            var token: String
            do {
                let reply = try await rpc(.getToken, input: [:], identity: identity, csrf: csrf, token: nil, jar: &jar)
                token = try Self.secret(reply["accessToken"])
            } catch RefreshFailure.invalidCredential {
                (token, csrf) = try await refresh(identity: identity, csrf: csrf, jar: &jar)
            }
            let input: [String: KiroCBOR.Value] = ["isEmailRequired": .bool(true), "origin": .string("KIRO_IDE"),
                                                   "profileArn": .string(identity.profileArn)]
            let reply: [String: KiroCBOR.Value]
            do { reply = try await rpc(.usage, input: input, identity: identity, csrf: csrf, token: token, jar: &jar) }
            catch RefreshFailure.invalidCredential {
                (token, csrf) = try await refresh(identity: identity, csrf: csrf, jar: &jar)
                reply = try await rpc(.usage, input: input, identity: identity, csrf: csrf, token: token, jar: &jar)
            }
            let updated = try WebProviderSession.credential(provider: .kiro, origin: Self.origin, accountID: accountID,
                accessToken: jar.header, expiresAt: jar.expiresAt, remoteAccountID: identity.userID,
                metadata: ["kiroProfileArn": identity.profileArn, "kiroIdp": identity.idp, "kiroCookieExpiries": try Self.expiryJSON(jar.expiries)])
            var snapshot = try KiroProviderParser.snapshot(reply, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = try Self.sourceIdentity(updated)
            return .init(snapshot: snapshot, updatedCredential: updated == credential ? nil : try updated.encoded())
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private enum Operation: String {
        case getToken = "GetToken", refresh = "RefreshToken", usage = "GetUserUsageAndLimits"
    }

    private func bootstrap(jar: inout Jar) async throws -> KiroPortalIdentity {
        var request = URLRequest(url: URL(string: Self.origin)!)
        request.httpMethod = "GET"; request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, _) = try await send(request, jar: &jar)
        return try KiroPortalIdentity.parse(data)
    }

    private func refresh(identity: KiroPortalIdentity, csrf: String, jar: inout Jar) async throws -> (String, String) {
        let reply = try await rpc(.refresh, input: ["csrfToken": .string(csrf)], identity: identity, csrf: csrf, token: nil, jar: &jar)
        if let profile = reply["profileArn"], profile.text != identity.profileArn { throw RefreshFailure.invalidCredential }
        return (try Self.secret(reply["accessToken"]), try Self.secret(reply["csrfToken"]))
    }

    private func rpc(_ operation: Operation, input: [String: KiroCBOR.Value], identity: KiroPortalIdentity,
                     csrf: String, token: String?, jar: inout Jar) async throws -> [String: KiroCBOR.Value] {
        let url = URL(string: Self.origin + "/service/KiroWebPortalService/operation/" + operation.rawValue)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = try KiroCBOR.encode(.map(input))
        request.setValue("application/cbor", forHTTPHeaderField: "Content-Type")
        request.setValue("application/cbor", forHTTPHeaderField: "Accept")
        request.setValue("rpc-v2-cbor", forHTTPHeaderField: "smithy-protocol")
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue(identity.userID, forHTTPHeaderField: "x-kiro-userid")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await send(request, jar: &jar)
        guard response.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first?.lowercased() == "application/cbor",
              let object = try KiroCBOR.decode(data).object else { throw RefreshFailure.unreadableResponse }
        return object
    }

    private func send(_ request: URLRequest, jar: inout Jar) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue(jar.header, forHTTPHeaderField: "Cookie")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard let url = response.url, url.scheme == "https", url.host == "app.kiro.dev", url.port == nil || url.port == 443,
              url.path == request.url?.path else { throw RefreshFailure.invalidCredential }
        if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        guard data.count <= 1_000_000 else { throw RefreshFailure.unreadableResponse }
        try jar.update(response, now: now())
        return (data, response)
    }

    private static func secret(_ value: KiroCBOR.Value?) throws -> String {
        guard let value = value?.text, !value.isEmpty, value.utf8.count <= 32_768,
              value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { throw RefreshFailure.unreadableResponse }
        return value
    }

    /// Cookie bytes authenticate the request; verified personal identity scopes the cache across renewal.
    static func sourceIdentity(_ credential: ProviderCredentialEnvelope) throws -> String {
        _ = try Jar(credential: credential)
        guard credential.provider == .kiro, try WebProviderSession.fingerprint(credential) == credential.metadata["sourceCredentialFingerprint"],
              credential.metadata["origin"] == origin, let local = credential.metadata["localAccountID"], UUID(uuidString: local) != nil,
              let remote = credential.accountID, !remote.isEmpty, remote.utf8.count <= 2_048,
              let profile = credential.metadata["kiroProfileArn"], !profile.isEmpty, profile.utf8.count <= 2_048,
              let idp = credential.metadata["kiroIdp"], ["Google", "Github", "BuilderId"].contains(idp) else { throw RefreshFailure.invalidCredential }
        let bytes = try JSONEncoder().encode(["kiro.portal.v1", origin, local, remote, profile, idp])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func expiryJSON(_ values: [String: Double]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(values), as: UTF8.self)
    }

    private struct Jar {
        var values: [String: String]
        var expiries: [String: Double]
        var expiresAt: Date? { expiries.values.min().map(Date.init(timeIntervalSince1970:)) }
        var header: String { values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ") }
        init(credential: ProviderCredentialEnvelope) throws {
            values = try cookiePolicy.values(in: credential.accessToken)
            guard let json = credential.metadata["kiroCookieExpiries"], json.utf8.count <= 65_536,
                  let data = json.data(using: .utf8), let table = try? JSONDecoder().decode([String: Double].self, from: data),
                  Set(table.keys).isSubset(of: Set(values.keys)),
                  table.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 32_503_680_000 && $0 == floor($0) }),
                  table.values.min().map(Date.init(timeIntervalSince1970:)) == credential.expiresAt else { throw RefreshFailure.invalidCredential }
            expiries = table
        }
        mutating func update(_ response: HTTPURLResponse, now: Date) throws {
            guard let url = response.url else { throw RefreshFailure.invalidCredential }
            let fields = response.allHeaderFields.reduce(into: [String: String]()) { values, pair in
                if let name = pair.key as? String, let value = pair.value as? String { values[name] = value }
            }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            var changed: Set<String> = []
            for cookie in cookies {
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard cookiePolicy.domains.contains(domain), cookie.path == "/", cookie.isSecure,
                      !cookiePolicy.deniedPrefixes.contains(where: { cookie.name.hasPrefix($0) }) else { continue }
                guard changed.insert(cookie.name).inserted else { throw RefreshFailure.invalidCredential }
                if cookie.value.isEmpty || cookie.expiresDate.map({ $0 <= now }) == true {
                    values.removeValue(forKey: cookie.name); expiries.removeValue(forKey: cookie.name)
                }
                else {
                    _ = try cookiePolicy.values(in: "\(cookie.name)=\(cookie.value)")
                    values[cookie.name] = cookie.value
                    if let date = cookie.expiresDate { expiries[cookie.name] = floor(date.timeIntervalSince1970) }
                    else { expiries.removeValue(forKey: cookie.name) }
                }
            }
            _ = try cookiePolicy.values(in: header)
        }
    }
}

struct KiroPortalIdentity: Equatable, Sendable {
    let userID: String
    let profileArn: String
    let idp: String
    let csrf: String

    static func parse(_ data: Data) throws -> Self {
        guard data.count <= 1_000_000, let html = String(data: data, encoding: .utf8) else { throw RefreshFailure.unreadableResponse }
        let clean = html.replacingOccurrences(of: #"<(script|style)\b[^>]*>[\s\S]*?</\1\s*>|<!--[\s\S]*?-->"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        guard let headRange = clean.range(of: #"<head\b[^>]*>([\s\S]*?)</head\s*>"#, options: [.regularExpression, .caseInsensitive]) else { throw RefreshFailure.unreadableResponse }
        let head = String(clean[headRange])
        let tags = try NSRegularExpression(pattern: #"<meta\b[^>]{0,4096}>"#, options: [.caseInsensitive])
        let attributes = try NSRegularExpression(pattern: #"\b([A-Za-z-]+)\s*=\s*(["'])(.*?)\2"#)
        var meta: [String: String] = [:]
        for match in tags.matches(in: head, range: NSRange(head.startIndex..., in: head)) {
            guard let range = Range(match.range, in: head) else { continue }
            let tag = String(head[range]); var fields: [String: String] = [:]
            for attribute in attributes.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard let keyRange = Range(attribute.range(at: 1), in: tag), let valueRange = Range(attribute.range(at: 3), in: tag) else { throw RefreshFailure.unreadableResponse }
                let key = tag[keyRange].lowercased()
                guard fields[key] == nil else { throw RefreshFailure.unreadableResponse }; fields[key] = String(tag[valueRange])
            }
            guard let name = fields["name"], ["stage", "user-status", "user-id", "profile-arn", "idp", "csrf-token"].contains(name) else { continue }
            guard meta[name] == nil, fields["content"] == nil || fields["value"] == nil,
                  let value = fields["content"] ?? fields["value"], value.utf8.count <= 2_048,
                  value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }), !value.contains("&") else { throw RefreshFailure.unreadableResponse }
            meta[name] = value
        }
        guard meta["stage"] == "prod", let status = meta["user-status"], !["anonymous", "stale"].contains(status.lowercased()),
              let idp = meta["idp"], ["Google", "Github", "BuilderId"].contains(idp),
              let user = meta["user-id"], !user.isEmpty, let csrf = meta["csrf-token"], !csrf.isEmpty else { throw RefreshFailure.invalidCredential }
        // Official Md/production profile mapping. These are service profile IDs, not personal identity.
        let profile = idp == "BuilderId" ? "arn:aws:codewhisperer:us-east-1:638616132270:profile/AAAACCCCXXXX"
            : "arn:aws:codewhisperer:us-east-1:699475941385:profile/EHGA3GRVQMUK"
        return Self(userID: user, profileArn: profile, idp: idp, csrf: csrf)
    }
}

enum KiroProviderParser {
    static func snapshot(_ root: [String: KiroCBOR.Value], accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let plan: String?
        if let value = root["subscriptionInfo"], value != .null {
            guard let info = value.object else { throw RefreshFailure.unreadableResponse }
            plan = try text(info, "subscriptionTitle")
        } else { plan = nil }
        let reset = try date(root, "nextDateReset")
        guard let list = root["usageBreakdownList"]?.list, list.count <= 64 else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = [], ids: Set<String> = []
        for value in list {
            guard let item = value.object, let resource = try text(item, "resourceType"), !resource.isEmpty else { throw RefreshFailure.unreadableResponse }
            guard ids.insert(resource).inserted else { throw RefreshFailure.unreadableResponse }
            let label = try text(item, "displayNamePlural") ?? text(item, "displayName") ?? resource
            let unit = try text(item, "unit") ?? label
            if let window = try window(item, id: "kiro.\(resource).monthly", name: label + "（订阅额度）", unit: unit, reset: reset, expiry: nil, period: .monthly) {
                windows.append(window)
            }
            if let trial = item["freeTrialInfo"], trial != .null {
                guard let trial = trial.object else { throw RefreshFailure.unreadableResponse }
                if try text(trial, "freeTrialStatus") == "ACTIVE" {
                    let expiry = try date(trial, "freeTrialExpiry")
                    if expiry.map({ $0 > collectedAt }) != false,
                       let window = try window(trial, id: "kiro.\(resource).trial", name: label + "（试用）", unit: unit, reset: nil, expiry: expiry, period: nil) { windows.append(window) }
                }
            }
            if let bonuses = item["bonuses"], bonuses != .null {
                guard let bonuses = bonuses.list, bonuses.count <= 64 else { throw RefreshFailure.unreadableResponse }
                var codes: Set<String> = []
                for bonus in bonuses {
                    guard let bonus = bonus.object else { throw RefreshFailure.unreadableResponse }
                    guard try text(bonus, "status") == "ACTIVE" else { continue }
                    guard let code = try text(bonus, "bonusCode"), !code.isEmpty, codes.insert(code).inserted else { throw RefreshFailure.unreadableResponse }
                    let expiry = try date(bonus, "expiresAt")
                    if expiry.map({ $0 > collectedAt }) != false,
                       let window = try window(bonus, id: "kiro.\(resource).bonus.\(code)", name: try text(bonus, "displayName") ?? "额外额度", unit: unit, reset: nil, expiry: expiry, period: nil) { windows.append(window) }
                }
            }
            if let credits = item["overageCredits"], credits != .null {
                guard let credits = credits.list, credits.count <= 64 else { throw RefreshFailure.unreadableResponse }
                var expiries: Set<Date> = []
                for credit in credits {
                    guard let credit = credit.object, let expiry = try date(credit, "expiresAt"), expiries.insert(expiry).inserted else { throw RefreshFailure.unreadableResponse }
                    if expiry > collectedAt, let window = try window(credit, id: "kiro.\(resource).credit.\(expiry.timeIntervalSince1970)",
                        name: label + "（额外 credits）", unit: unit, reset: nil, expiry: expiry, period: nil) { windows.append(window) }
                }
            }
        }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: plan,
            quotaStatusText: windows.isEmpty ? "服务未提供可显示的额度池" : nil)
    }

    private static func window(_ item: [String: KiroCBOR.Value], id: String, name: String, unit: String,
                               reset: Date?, expiry: Date?, period: QuotaPeriod?) throws -> QuotaWindow? {
        let used = try number(item, "currentUsageWithPrecision") ?? number(item, "currentUsage")
        let total = try number(item, "usageLimitWithPrecision") ?? number(item, "usageLimit")
        guard used != nil || total != nil else { return nil }
        let ratio = used.flatMap { used in total.flatMap { $0 > 0 ? used / $0 * 100 : nil } }
        guard ratio?.isFinite != false else { throw RefreshFailure.unreadableResponse }
        let remaining = used.flatMap { used in total.map { max(0, $0 - used) } }
        return QuotaWindow(id: id, name: name, scope: nil, period: period,
            isExhausted: used.flatMap { used in total.map { used >= $0 } }, usedPercentage: ratio,
            remainingCount: remaining, totalCount: total, resetsAt: reset, unit: unit, expiresAt: expiry,
            exactCounts: DecimalQuotaCounts(used: used.flatMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) },
                remaining: remaining.flatMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) },
                total: total.flatMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }),
            resetSemantics: period == nil ? .nonResettingAllowance : nil)
    }

    private static func number(_ object: [String: KiroCBOR.Value], _ key: String) throws -> Double? {
        guard let value = object[key], value != .null else { return nil }
        guard let number = value.numeric, number.isFinite, number >= 0 else { throw RefreshFailure.unreadableResponse }
        return number
    }
    private static func text(_ object: [String: KiroCBOR.Value], _ key: String) throws -> String? {
        guard let value = object[key], value != .null else { return nil }
        guard let text = value.text, !text.isEmpty, text.utf8.count <= 256,
              !text.unicodeScalars.contains(where: { $0.value < 32 }) else { throw RefreshFailure.unreadableResponse }
        return text
    }
    private static func date(_ object: [String: KiroCBOR.Value], _ key: String) throws -> Date? {
        guard let value = object[key], value != .null else { return nil }
        guard let date = value.date else { throw RefreshFailure.unreadableResponse }
        return date
    }
}
