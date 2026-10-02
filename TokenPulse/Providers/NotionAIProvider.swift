import Foundation

struct NotionAIProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let origin = "https://app.notion.com"
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["notion.com", "app.notion.com", "www.notion.com"], path: "/api/v3/",
        names: ["token_v2"], requiredNames: ["token_v2"])
    struct Workspace: Equatable, Sendable {
        let id: String
        let userID: String
        let name: String
        let tier: String?
    }
    static var loginProfile: WebProviderLoginProfile {
        .init(loginURL: URL(string: "https://www.notion.com/login")!,
              allowedOrigins: [origin, "https://notion.com", "https://www.notion.com", "https://notion.so", "https://www.notion.so", "https://accounts.google.com", "https://appleid.apple.com", "https://login.microsoftonline.com"]) { cookies, _, id, now in
            try await credentialChoices(cookies, accountID: id, now: now)
        }
    }
    static func credentialChoices(_ cookies: [HTTPCookie], accountID: UUID, now: Date,
                                  transport: any ProviderTransport = URLSessionProviderTransport.rejectingRedirects()) async throws -> [WebLoginCredentialChoice] {
        let base = try WebProviderSession.cookieCredential(cookies: cookies, policy: cookiePolicy, provider: .notionAI,
                                                           origin: origin, accountID: accountID, now: now)
        let client = NotionAIProviderClient(transport: transport, now: { now })
        let spaces = try await client.workspaces(accountID: accountID, credential: base)
        guard !spaces.isEmpty else { throw RefreshFailure.subscriptionRequired }
        return try spaces.map { space in
            let scoped = try WebProviderSession.credential(provider: .notionAI, origin: origin, accountID: accountID,
                accessToken: base.accessToken, expiresAt: base.expiresAt, remoteAccountID: space.userID,
                metadata: ["workspaceID": space.id])
            let title = "\(space.name) · \(space.tier ?? "套餐未提供") · \(space.id.prefix(8))"
            return .init(id: space.id, title: title, credential: try scoped.encoded())
        }
    }
    func workspaces(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> [Workspace] {
        try WebProviderSession.validate(credential, provider: .notionAI, accountID: accountID, origins: [Self.origin], now: now())
        _ = try Self.cookiePolicy.values(in: credential.accessToken)
        return try Self.parseWorkspaces(await post("getSpaces", body: [:], cookie: credential.accessToken))
    }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .notionAI, accountID: accountID, origins: [Self.origin], now: now())
        guard let rawID = credential.metadata["workspaceID"], let uuid = UUID(uuidString: rawID) else { throw RefreshFailure.invalidCredential }
        let selectedID = uuid.uuidString.lowercased()
        let spaces = try await workspaces(accountID: accountID, credential: credential)
        guard let chosen = spaces.first(where: { $0.id == selectedID }), chosen.userID == credential.accountID else {
            throw RefreshFailure.invalidCredential
        }
        let data = try await post("getCreditRateLimitStatus", body: ["spaceId": chosen.id], cookie: credential.accessToken)
        var snapshot = try Self.snapshot(data, accountID: accountID, workspaceID: chosen.id,
                                         workspaceName: chosen.name, planName: chosen.tier, collectedAt: now())
        snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
        return .init(snapshot: snapshot, updatedCredential: nil)
    }
    private func post(_ method: String, body: [String: String], cookie: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(Self.origin)/api/v3/\(method)")!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        request.setValue(Self.origin + "/", forHTTPHeaderField: "Referer")
        let secured: any ProviderTransport = transport is URLSessionProviderTransport ? URLSessionProviderTransport.rejectingRedirects() : transport
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: secured)
            if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return data
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    static func parseWorkspaces(_ data: Data) throws -> [Workspace] {
        let root = try ProviderHTTP.json(data)
        let identified = root.keys.filter { key in
            guard let container = root[key] as? [String: Any], let users = container["notion_user"] as? [String: Any],
                  let entry = users[key], let record = record(entry) else { return false }
            return record["id"] as? String == key
        }
        let userID: String
        if identified.count == 1 { userID = identified[0] }
        else if identified.isEmpty, root.count == 1, let only = root.keys.first { userID = only }
        else { throw RefreshFailure.unreadableResponse }
        guard let container = root[userID] as? [String: Any], let spaces = container["space"] as? [String: Any] else {
            throw RefreshFailure.unreadableResponse
        }
        var seen: Set<String> = []
        return try spaces.keys.sorted().map { key in
            guard let entry = spaces[key], let fields = record(entry),
                  let keyUUID = UUID(uuidString: key), let valueUUID = UUID(uuidString: fields["id"] as? String ?? key),
                  keyUUID == valueUUID else { throw RefreshFailure.unreadableResponse }
            let id = valueUUID.uuidString.lowercased()
            guard seen.insert(id).inserted else { throw RefreshFailure.unreadableResponse }
            let rawName = (fields["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName?.isEmpty == false ? String(rawName!.prefix(256)) : id
            let rawTier = (fields["subscription_tier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let tier = rawTier?.isEmpty == false ? rawTier!.prefix(1).uppercased() + rawTier!.dropFirst() : nil
            return Workspace(id: id, userID: userID, name: name, tier: tier)
        }
    }
    private static func record(_ raw: Any) -> [String: Any]? {
        guard var value = raw as? [String: Any] else { return nil }
        for _ in 0..<2 {
            if let nested = value["value"] as? [String: Any] { value = nested } else { break }
        }
        return value
    }
    private struct Reply: Decodable {
        struct Window: Decodable {
            let creditType: String?
            let window: String?
            let used: WalletDecimalValue?
            let limit: WalletDecimalValue?
            let periodEndMs: WalletDecimalValue?
        }
        let status: String?
        let window: Window?
        let resetsInSeconds: WalletDecimalValue?
        let billingPeriodWindow: Window?
    }
    static func snapshot(_ data: Data, accountID: UUID, workspaceID: String, workspaceName: String? = nil,
                         planName: String? = nil, collectedAt: Date) throws -> QuotaSnapshot {
        guard UUID(uuidString: workspaceID) != nil,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        if reply.status?.lowercased() == "not_applicable" {
            return .init(accountID: accountID, windows: [], collectedAt: collectedAt, providerPlanName: planName,
                         quotaStatusText: "所选工作区没有适用的 Notion AI 额度")
        }
        guard reply.window != nil || reply.billingPeriodWindow != nil else { throw RefreshFailure.unreadableResponse }
        let prefix = workspaceName.map { "\($0) · " } ?? ""
        var windows: [QuotaWindow] = []
        for (raw, id, label, period, reset) in [
            (reply.window, "rolling", durationName(reply.window?.window), durationPeriod(reply.window?.window),
             reply.resetsInSeconds.flatMap { secondsDate($0.amount, relativeTo: collectedAt) }),
            (reply.billingPeriodWindow, "billing", "账期 AI 额度", QuotaPeriod.monthly,
             reply.billingPeriodWindow?.periodEndMs.flatMap { millisecondsDate($0.amount) }),
        ] {
            guard let raw else { continue }
            if let type = raw.creditType, type != "basic_ai_credits" { throw RefreshFailure.unreadableResponse }
            let used = raw.used?.amount, total = raw.limit?.amount
            guard used.map({ $0 >= 0 }) != false, total.map({ $0 > 0 }) != false,
                  used != nil || total != nil else { continue }
            let remaining: Decimal?
            if let used, let total { remaining = exactDifference(total, used) } else { remaining = nil }
            let percentage = used.flatMap { used in total.flatMap { HostedQuotaMath.percentage(used: used, limit: $0) } }
            windows.append(QuotaWindow(id: "notionAI.\(workspaceID).\(id)", name: prefix + label, scope: nil, period: period,
                isExhausted: used.flatMap { used in total.map { used >= $0 } }, usedPercentage: percentage,
                remainingCount: nil, totalCount: nil, resetsAt: reset, unit: "AI credits",
                exactCounts: .init(used: used, remaining: remaining, total: total)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: planName)
    }
    private static func durationSeconds(_ token: String?) -> Int? {
        guard let raw = token?.trimmingCharacters(in: .whitespaces).lowercased(), let unit = raw.last,
              let count = Int(raw.dropLast()), count > 0, let scale = ["m": 60, "h": 3600, "d": 86400, "w": 604800][String(unit)] else { return nil }
        let result = count.multipliedReportingOverflow(by: scale)
        return result.overflow ? nil : result.partialValue
    }
    private static func durationPeriod(_ token: String?) -> QuotaPeriod { QuotaPeriod(seconds: durationSeconds(token)) }
    private static func durationName(_ token: String?) -> String {
        guard let seconds = durationSeconds(token) else { return "滚动 AI 额度" }
        return seconds % 3600 == 0 ? "\(seconds / 3600) 小时 AI 额度" : "滚动 AI 额度"
    }
    private static func secondsDate(_ amount: Decimal, relativeTo now: Date) -> Date? {
        guard amount >= 0 else { return nil }
        let seconds = NSDecimalNumber(decimal: amount).doubleValue
        let date = now.addingTimeInterval(seconds)
        return seconds.isFinite && Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded()) != nil ? date : nil
    }
    private static func millisecondsDate(_ amount: Decimal) -> Date? {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        guard amount > 0, value.isFinite, Int64(exactly: value.rounded()) != nil else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
    private static func exactDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        if rhs >= lhs { return 0 }
        var a = lhs, b = rhs, result = Decimal(), reverse = Decimal()
        guard NSDecimalSubtract(&result, &a, &b, .plain) == .noError,
              NSDecimalSubtract(&reverse, &a, &result, .plain) == .noError, reverse == rhs else { return nil }
        return result
    }
}
