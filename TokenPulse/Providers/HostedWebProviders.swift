import Foundation
import CoreFoundation

enum HostedWebProfiles {
    static func policy(_ provider: Provider) -> CookieWebSessionPolicy {
        switch provider {
        case .raycastAI:
            return .init(domains: ["raycast.com", "www.raycast.com"], path: "/frontend_api/current_user/ai_credits",
                         names: ["__raycast_session", "csrf_token"], requiredNames: ["__raycast_session"])
        case .t3Chat:
            // The service has no published stable session cookie name. Replay
            // cookies from this isolated site's jar, never another browser.
            return .init(domains: ["t3.chat"], path: "/api/trpc/getCustomerData", includeAllNames: true,
                         deniedPrefixes: ["_ga", "_gid", "_gat"])
        default:
            // Only parent-domain cookies can be replayed on both Zoom API hosts.
            return .init(domains: ["zoom.us"], path: "/ai-computer/api/v1/credits/status", includeAllNames: true,
                         deniedPrefixes: ["_ga", "_gid", "_gat"])
        }
    }
    static func origin(_ provider: Provider) -> String {
        switch provider {
        case .raycastAI: "https://www.raycast.com"
        case .t3Chat: "https://t3.chat"
        default: "https://zoommate.zoom.us"
        }
    }
    static func profile(_ provider: Provider) -> WebProviderLoginProfile {
        let origin = origin(provider)
        let url = provider == .raycastAI ? origin + "/settings" : provider == .t3Chat ? origin + "/settings/customization" : origin + "/"
        return .init(loginURL: URL(string: url)!, allowedOrigins: [origin]) { cookies, _, accountID, now in
            let envelope = try WebProviderSession.cookieCredential(cookies: cookies, policy: policy(provider),
                provider: provider, origin: origin, accountID: accountID, now: now)
            return [.init(id: accountID.uuidString, title: provider.displayName, credential: try envelope.encoded())]
        }
    }
    static func validate(_ credential: ProviderCredentialEnvelope, provider: Provider, accountID: UUID, now: Date) throws {
        try WebProviderSession.validate(credential, provider: provider, accountID: accountID, origins: [origin(provider)], now: now)
        _ = try policy(provider).values(in: credential.accessToken)
    }
}

enum HostedWebHTTP {
    struct StatusFailure: Error { let status: Int; let failure: RefreshFailure }
    static func get(_ url: URL, credential: ProviderCredentialEnvelope, headers: [String: String] = [:],
                    transport: any ProviderTransport, reportHTTPStatus: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(credential.accessToken, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credential.metadata["origin"], forHTTPHeaderField: "Origin")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == url.scheme, response.url?.host == url.host,
              response.url?.port == url.port else { throw RefreshFailure.invalidCredential }
        if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) {
            if reportHTTPStatus { throw StatusFailure(status: response.statusCode, failure: failure) }
            throw failure
        }
        guard data.count <= 2_097_152 else { throw RefreshFailure.unreadableResponse }
        return data
    }
    static func numeric(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }
    static func epoch(_ raw: Double?, millisecondsOnly: Bool = false) -> Date? {
        guard let raw, raw > 0, raw.isFinite else { return nil }
        let seconds = millisecondsOnly || raw > 10_000_000_000 ? raw / 1000 : raw
        guard Int64(exactly: (seconds * 1000).rounded()) != nil else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    static func difference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        if rhs >= lhs { return 0 }
        var lhs = lhs, rhs = rhs, result = Decimal(), recovered = Decimal()
        guard NSDecimalSubtract(&result, &lhs, &rhs, .plain) == .noError,
              NSDecimalSubtract(&recovered, &lhs, &result, .plain) == .noError, recovered == rhs else { return nil }
        return result
    }
}

struct RaycastAIProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try HostedWebProfiles.validate(credential, provider: .raycastAI, accountID: accountID, now: now())
            let data = try await HostedWebHTTP.get(URL(string: "https://www.raycast.com/frontend_api/current_user/ai_credits")!,
                credential: credential, headers: ["Referer": "https://www.raycast.com/settings"], transport: transport)
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    private struct Reply: Decodable {
        struct Funding: Decodable { let tier: String? }
        let remaining_balance_credits: HostedQuotaAmount?
        let total_balance_credits: HostedQuotaAmount?
        let next_credits_at: String?
        let funding_subscription: Funding?
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        let remaining = reply.remaining_balance_credits?.nonnegative
        let total = reply.total_balance_credits?.nonnegative
        guard remaining != nil || total != nil else { throw RefreshFailure.noQuotaWindows }
        let used = total.flatMap { cap in remaining.flatMap { HostedWebHTTP.difference(cap, $0) } }
        let percentage = total.flatMap { total in used.flatMap { HostedQuotaMath.percentage(used: $0, limit: total) } }
        let window = QuotaWindow(id: "raycast.ai_credits", name: "AI credits", scope: nil, period: .other,
            isExhausted: total.map { $0 > 0 } == true ? remaining.map { $0 == 0 } : nil,
            usedPercentage: percentage, remainingCount: nil, totalCount: nil,
            resetsAt: KeyQuotaRequest.date(reply.next_credits_at), unit: "credits",
            exactCounts: .init(used: used, remaining: remaining, total: total))
        let tier = reply.funding_subscription?.tier
        let plan = tier.map { ["pro": "Pro", "pro_plus": "Pro+", "max": "Max"][$0] ?? $0 }
        return .init(accountID: accountID, windows: [window], collectedAt: collectedAt, providerPlanName: plan)
    }
}

struct T3ChatProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static var endpoint: URL {
        var url = URLComponents(string: "https://t3.chat/api/trpc/getCustomerData")!
        url.queryItems = [.init(name: "batch", value: "1"), .init(name: "input", value: #"{"0":{"json":{"sessionId":null},"meta":{"values":{"sessionId":["undefined"]}}}}"#)]
        return url.url!
    }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try HostedWebProfiles.validate(credential, provider: .t3Chat, accountID: accountID, now: now())
            let data = try await HostedWebHTTP.get(Self.endpoint, credential: credential, headers: [
                "Referer": "https://t3.chat/settings/customization", "trpc-accept": "application/jsonl",
                "x-trpc-source": "web-client", "x-trpc-batch": "true"], transport: transport)
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    /// Resolve only the requested batch item -> result -> data chain. Ignore
    /// unrelated stream records even if they contain quota-shaped field names.
    static func customer(_ data: Data) throws -> [String: Any] {
        guard data.count <= 2_097_152, let text = String(data: data, encoding: .utf8) else { throw RefreshFailure.unreadableResponse }
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty, lines.count <= 256 else { throw RefreshFailure.unreadableResponse }
        let values = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
        if values.count == 1 {
            let root = (values[0] as? [[String: Any]])?.first ?? (values[0] as? [String: Any])
            if let result = root?["result"] as? [String: Any], let data = result["data"] as? [String: Any] {
                return data["json"] as? [String: Any] ?? data
            }
        }
        guard let header = values.first as? [String: Any], let json = header["json"] as? [String: Any],
              let root = json["0"] as? [Any], root.count == 2,
              let promise = root[1] as? [Any], promise.count == 3,
              let firstID = streamID(promise[2]) else { throw RefreshFailure.unreadableResponse }
        var frames: [Int: [Any]] = [:]
        for value in values.dropFirst() {
            guard let object = value as? [String: Any], let frame = object["json"] as? [Any], frame.count == 3,
                  let id = streamID(frame[0]), streamID(frame[1]) == 0, let payload = frame[2] as? [Any],
                  frames[id] == nil else { throw RefreshFailure.unreadableResponse }
            frames[id] = payload
        }
        var id = firstID
        for key in ["result", "data"] {
            guard let payload = frames[id], payload.count == 2,
                  let wrapped = payload[0] as? [[String: Any]], wrapped.count == 1, wrapped[0][key] != nil,
                  let reference = payload[1] as? [Any], reference.count == 3,
                  reference[0] as? String == key, streamID(reference[1]) == 0,
                  let next = streamID(reference[2]), next != id else { throw RefreshFailure.unreadableResponse }
            id = next
        }
        guard let payload = frames[id], payload.count == 1,
              let wrapped = payload[0] as? [[String: Any]], wrapped.count == 1 else { throw RefreshFailure.unreadableResponse }
        return wrapped[0]
    }
    private static func streamID(_ value: Any) -> Int? {
        guard let number = HostedWebHTTP.numeric(value), number >= 0, number <= 100_000,
              number.rounded() == number else { return nil }
        return Int(number)
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let customer = try customer(data)
        let subscription = customer["subscription"] as? [String: Any]
        let fields: [(String, String, String, QuotaPeriod, Any?)] = [
            ("usageFourHourPercentage", "four_hour", "4 小时额度", .other, customer["usageFourHourNextResetAt"] ?? customer["usageWindowNextResetAt"]),
            ("usageMonthPercentage", "monthly", "每月额度", .monthly, subscription?["currentPeriodEnd"]),
        ]
        let windows = try fields.compactMap { field, id, name, period, reset -> QuotaWindow? in
            guard let raw = customer[field] else { return nil }
            guard let percentage = HostedWebHTTP.numeric(raw), percentage >= 0 else { throw RefreshFailure.unreadableResponse }
            return .init(id: "t3chat.\(id)", name: name, scope: nil, period: period, isExhausted: percentage >= 100,
                usedPercentage: percentage, remainingCount: nil, totalCount: nil,
                resetsAt: HostedWebHTTP.epoch(HostedWebHTTP.numeric(reset)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
            providerPlanName: (subscription?["productName"] as? String) ?? (customer["subTier"] as? String))
    }
}

struct ZoomMateProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try HostedWebProfiles.validate(credential, provider: .zoomMate, accountID: accountID, now: now())
            for host in ["ai.zoom.us", "zoommate.zoom.us"] {
                do {
                    var login = URLComponents(string: "https://\(host)/ai-computer/api/v1/login/")!
                    login.queryItems = [.init(name: "continue", value: "https://zoommate.zoom.us/")]
                    let data = try await HostedWebHTTP.get(login.url!, credential: credential,
                        headers: ["Referer": "https://zoommate.zoom.us/"], transport: transport, reportHTTPStatus: true)
                    let token = try Self.token(data)
                    let status = try await HostedWebHTTP.get(URL(string: "https://\(host)/ai-computer/api/v1/credits/status")!,
                        credential: credential, headers: ["Referer": "https://zoommate.zoom.us/", "Authorization": "Bearer \(token)"], transport: transport, reportHTTPStatus: true)
                    var snapshot = try Self.snapshot(status, accountID: accountID, collectedAt: now())
                    snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
                    return .init(snapshot: snapshot, updatedCredential: nil)
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    if let http = error as? HostedWebHTTP.StatusFailure {
                        guard host == "ai.zoom.us", (500..<600).contains(http.status) else { throw http.failure }
                        continue
                    }
                    let mapped = ProviderHTTP.refreshFailure(error)
                    guard host == "ai.zoom.us", mapped as? RefreshFailure == .network else { throw mapped }
                }
            }
            throw RefreshFailure.network
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    private struct Login: Decodable { struct Body: Decodable { let nak: String? }; let success: Bool?; let data: Body? }
    static func token(_ data: Data) throws -> String {
        let reply = try KeyQuotaRequest.decode(Login.self, from: data)
        if reply.success == false { throw RefreshFailure.invalidCredential }
        guard let token = reply.data?.nak, !token.isEmpty, token.utf8.count <= 16_384,
              token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { throw RefreshFailure.unreadableResponse }
        return token
    }
    private struct Reply: Decodable {
        struct Body: Decodable { let credit_status: Status? }
        struct Status: Decodable {
            let budget_cap: HostedQuotaAmount?; let used_credit: HostedQuotaAmount?; let remaining_credit: HostedQuotaAmount?
            let overage_credit: HostedQuotaAmount?; let allow_overage: Bool?; let is_quota_available: Bool?; let is_unlimited: Bool?
            let cycle_start_date: Double?; let cycle_end_date: Double?
        }
        let data: Body?
        let status_code: Int?
        let error_message: String?
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        guard reply.status_code == nil || reply.status_code == 200,
              reply.error_message?.isEmpty != false,
              let status = reply.data?.credit_status else { throw RefreshFailure.unreadableResponse }
        let total = status.budget_cap?.nonnegative, reportedRemaining = status.remaining_credit?.nonnegative
        let used = status.used_credit?.nonnegative ?? total.flatMap { total in reportedRemaining.flatMap { HostedWebHTTP.difference(total, $0) } }
        let remaining = reportedRemaining ?? total.flatMap { total in used.flatMap { HostedWebHTTP.difference(total, $0) } }
        guard status.is_unlimited == true || used != nil || remaining != nil || total != nil || status.is_quota_available == false else { throw RefreshFailure.noQuotaWindows }
        let percentage = status.is_unlimited == true ? nil : total.flatMap { total in used.flatMap { HostedQuotaMath.percentage(used: $0, limit: total) } }
        let exhausted = status.is_unlimited == true ? nil : status.is_quota_available == false ? true
            : status.allow_overage == true ? false : total.flatMap { cap in used.map { $0 >= cap } }
        let window = QuotaWindow(id: "zoommate.credits", name: "credits 预算", scope: nil, period: .other,
            isExhausted: exhausted, isUnlimited: status.is_unlimited == true, usedPercentage: percentage,
            remainingCount: nil, totalCount: nil, resetsAt: HostedWebHTTP.epoch(status.cycle_end_date, millisecondsOnly: true), unit: "credits",
            overagePermitted: status.allow_overage, overageCount: status.overage_credit?.nonnegative.map { NSDecimalNumber(decimal: $0).doubleValue },
            exactCounts: status.is_unlimited == true ? nil : .init(used: used, remaining: remaining, total: total))
        return .init(accountID: accountID, windows: [window], collectedAt: collectedAt,
            quotaStatusText: status.is_quota_available == false ? "服务当前不允许使用这项额度" : nil)
    }
}
