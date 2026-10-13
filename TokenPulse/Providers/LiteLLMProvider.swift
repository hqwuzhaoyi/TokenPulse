import Foundation

struct LiteLLMProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    struct Identity: Equatable, Sendable { let user: String?; let team: String? }
    private struct KeyReply: Decodable {
        struct Info: Decodable { let user_id: String?; let team_id: String?; let status: String?; let blocked: Bool? }
        let info: Info
    }
    private struct Budget: Decodable {
        let user_id: String?
        let team_id: String?
        let spend: GatewayAmount?
        let max_budget: GatewayAmount?
        let budget_duration: String?
        let budget_reset_at: String?
    }
    private struct UserReply: Decodable { let user_id: String?; let user_info: Budget; let teams: [Budget]? }
    private struct TeamReply: Decodable { let team_id: String?; let team_info: Budget }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            let base = try GatewayCredentials.base(credential, provider: .liteLLM)
            let (keyData, keyHTTP) = try await GatewayQuotaSupport.reply("key/info", base: base, credential: credential, transport: transport)
            var snapshot: QuotaSnapshot
            if keyHTTP.statusCode == 403 || keyHTTP.statusCode == 404 {
                snapshot = Self.status("此 Key 无权读取预算信息", accountID: accountID, at: now())
            } else {
                if let failure = ProviderHTTP.queryFailure(status: keyHTTP.statusCode) { throw failure }
                let identity = try Self.identity(keyData)
                if let user = identity.user {
                    let (data, response) = try await GatewayQuotaSupport.reply("user/info", base: base, credential: credential, transport: transport,
                                                                               query: [URLQueryItem(name: "user_id", value: user)])
                    snapshot = try Self.read(data, response: response, identity: identity, accountID: accountID, at: now())
                } else if let team = identity.team {
                    let (data, response) = try await GatewayQuotaSupport.reply("team/info", base: base, credential: credential, transport: transport,
                                                                               query: [URLQueryItem(name: "team_id", value: team)])
                    snapshot = try Self.read(data, response: response, identity: identity, accountID: accountID, at: now())
                } else {
                    snapshot = Self.status("Key 未绑定可读取的用户或团队预算", accountID: accountID, at: now())
                }
            }
            snapshot.sourceCredentialFingerprint = GatewayCredentials.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func identity(_ data: Data) throws -> Identity {
        guard let reply = try? JSONDecoder().decode(KeyReply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        if reply.info.blocked == true || ["expired", "revoked", "deleted"].contains(reply.info.status?.lowercased() ?? "") { throw RefreshFailure.invalidCredential }
        return Identity(user: try identifier(reply.info.user_id), team: try identifier(reply.info.team_id))
    }

    private static func read(_ data: Data, response: HTTPURLResponse, identity: Identity, accountID: UUID, at: Date) throws -> QuotaSnapshot {
        if response.statusCode == 403 || response.statusCode == 404 {
            return status("此 Key 无权读取用户或团队预算", accountID: accountID, at: at)
        }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return identity.user != nil ? try userSnapshot(data, identity: identity, accountID: accountID, at: at)
            : try teamSnapshot(data, identity: identity, accountID: accountID, at: at)
    }

    static func userSnapshot(_ data: Data, identity: Identity, accountID: UUID, at: Date) throws -> QuotaSnapshot {
        guard let expectedUser = identity.user, let reply = try? JSONDecoder().decode(UserReply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        try verify([reply.user_id, reply.user_info.user_id], expected: expectedUser)
        var windows: [QuotaWindow] = []
        if let team = identity.team {
            let matching = (reply.teams ?? []).filter { $0.team_id == team }
            guard matching.count <= 1 else { throw RefreshFailure.unreadableResponse }
            if let budget = matching.first { windows.append(try window(budget, identity: team, isTeam: true)) }
        }
        windows.append(try window(reply.user_info, identity: expectedUser, isTeam: false))
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: at,
                             quotaStatusText: windows.allSatisfy { $0.usedPercentage == nil } ? "未提供可计算的预算上限或用量" : nil)
    }

    static func teamSnapshot(_ data: Data, identity: Identity, accountID: UUID, at: Date) throws -> QuotaSnapshot {
        guard let expectedTeam = identity.team, let reply = try? JSONDecoder().decode(TeamReply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        try verify([reply.team_id, reply.team_info.team_id], expected: expectedTeam)
        let window = try window(reply.team_info, identity: expectedTeam, isTeam: true)
        return QuotaSnapshot(accountID: accountID, windows: [window], collectedAt: at,
                             quotaStatusText: window.usedPercentage == nil ? "未提供可计算的团队预算上限或用量" : nil)
    }

    private static func window(_ budget: Budget, identity: String, isTeam: Bool) throws -> QuotaWindow {
        let spent = budget.spend?.value
        let maximum = budget.max_budget?.value
        guard spent.map({ $0 >= 0 }) ?? true, maximum.map({ $0 >= 0 }) ?? true else { throw RefreshFailure.unreadableResponse }
        let positiveLimit = maximum.flatMap { $0 > 0 ? $0 : nil }
        let remaining: Decimal?
        if let limit = positiveLimit, let spent { remaining = try GatewayQuotaSupport.checkedAdd(limit, -spent) }
        else { remaining = nil }
        let name = (isTeam ? "团队预算" : "用户预算") + (positiveLimit == nil ? "（上限未提供）" : "")
        return QuotaWindow(id: "liteLLM." + GatewayQuotaSupport.id([isTeam ? "team" : "user", identity]), name: name,
                           scope: (isTeam ? "团队 · " : "用户 · ") + identity, period: period(budget.budget_duration),
                           usedPercentage: try GatewayQuotaSupport.percentage(used: spent, total: positiveLimit),
                           remainingCount: nil, totalCount: nil, resetsAt: try GatewayQuotaSupport.date(budget.budget_reset_at), unit: "USD 预算额度",
                           exactCounts: .init(used: spent, remaining: remaining, total: positiveLimit))
    }

    static func period(_ raw: String?) -> QuotaPeriod {
        guard let raw, !raw.isEmpty else { return .other }
        let text = raw.lowercased()
        if text == "1mo" { return .monthly }
        let digits = text.prefix { $0 >= "0" && $0 <= "9" }
        guard let count = Int(digits), count > 0 else { return .other }
        let factor: Int = switch text.dropFirst(digits.count) { case "s": 1; case "m": 60; case "h": 3600; case "d": 86400; case "w": 604800; default: 0 }
        let seconds = count.multipliedReportingOverflow(by: factor)
        guard factor > 0, !seconds.overflow else { return .other }
        return QuotaPeriod(seconds: seconds.partialValue)
    }

    private static func verify(_ answers: [String?], expected: String) throws {
        let present = answers.compactMap { $0 }
        guard !present.isEmpty, present.allSatisfy({ $0 == expected }) else { throw RefreshFailure.unreadableResponse }
    }
    private static func identifier(_ raw: String?) throws -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard raw.utf8.count <= 1024, raw.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw RefreshFailure.unreadableResponse }
        return raw
    }
    private static func status(_ text: String, accountID: UUID, at: Date) -> QuotaSnapshot {
        QuotaSnapshot(accountID: accountID, windows: [], collectedAt: at, quotaStatusText: text)
    }
}
