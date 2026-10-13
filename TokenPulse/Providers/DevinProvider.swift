import Foundation

/// Only the observed app.devin.ai storage structure is imported. No editor/cache fallback.
enum DevinWebSession {
    static let origin = "https://app.devin.ai"
    static let organizationPrefix = "last-internal-org-for-external-org-v1-"

    static func credentials(storage: [String: String], accountID: UUID, origin: String = DevinWebSession.origin) throws -> [WebLoginCredentialChoice] {
        guard origin == Self.origin, let raw = storage["auth1_session"], raw.utf8.count <= 65_536,
              let root = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let token = root["token"] as? String, validToken(token),
              let user = root["userId"] as? String, validUser(user) else { throw RefreshFailure.invalidCredential }
        let organizations = Set(storage.filter { $0.key.hasPrefix(organizationPrefix) }.values.compactMap { raw -> String? in
            let value = (try? JSONDecoder().decode(String.self, from: Data(raw.utf8))) ?? raw
            return validOrganization(value) ? value : nil
        })
        guard !organizations.isEmpty, organizations.count <= 64 else { throw RefreshFailure.invalidCredential }
        return try organizations.sorted().map { organization in
            let envelope = try WebProviderSession.credential(provider: .devin, origin: origin, accountID: accountID,
                accessToken: token, remoteAccountID: user, metadata: ["organizationID": organization])
            return WebLoginCredentialChoice(id: organization, title: L10n.format("组织 %@", organization), credential: try envelope.encoded())
        }
    }

    static func validToken(_ value: String) -> Bool {
        value.hasPrefix("auth1_") && value.utf8.count > 20 && value.utf8.count <= 65_536
            && value.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
    static func validOrganization(_ value: String) -> Bool {
        value.range(of: #"\Aorg[-_][A-Fa-f0-9]{32}\z"#, options: .regularExpression) != nil
    }
    static func validUser(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...90).contains($0.value)
                || (97...122).contains($0.value) || $0.value == 45 || $0.value == 95 }
    }
}

struct DevinProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .devin, accountID: accountID,
            origins: [DevinWebSession.origin], now: now())
        guard DevinWebSession.validToken(credential.accessToken), let user = credential.accountID, DevinWebSession.validUser(user),
              let organization = credential.metadata["organizationID"], DevinWebSession.validOrganization(organization) else {
            throw RefreshFailure.invalidCredential
        }
        do {
            // Both spellings scope to the same internal organization. Only a 404 warrants a second spelling.
            for (index, path) in [organization, "organizations/\(organization)"].enumerated() {
                var request = URLRequest(url: URL(string: "\(DevinWebSession.origin)/api/\(path)/billing/quota/usage")!)
                request.httpMethod = "GET"
                request.timeoutInterval = 20
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.httpShouldHandleCookies = false
                request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(organization, forHTTPHeaderField: "x-cog-org-id")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await ProviderHTTP.send(request, transport: transport)
                if response.statusCode == 404, index == 0 { continue }
                if 300..<400 ~= response.statusCode { throw RefreshFailure.invalidCredential }
                if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
                var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
                snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
                return ProviderQueryResult(snapshot: snapshot, updatedCredential: nil)
            }
            throw RefreshFailure.server
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Timestamp: Decodable {
        let date: Date?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self), let parsed = ProviderHTTP.isoDate(string) { date = parsed; return }
            let decimal = try WalletDecimalValue(from: decoder).amount
            let raw = NSDecimalNumber(decimal: decimal).doubleValue
            guard raw.isFinite, raw >= 0 else { throw RefreshFailure.unreadableResponse }
            let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
            guard seconds <= 253_402_300_799 else { throw RefreshFailure.unreadableResponse }
            date = raw == 0 ? nil : Date(timeIntervalSince1970: seconds)
        }
    }
    private struct Reply: Decodable {
        let daily_percentage: WalletDecimalValue?
        let weekly_percentage: WalletDecimalValue?
        let daily_reset_at: Timestamp?
        let weekly_reset_at: Timestamp?
        let hide_daily_quota: Bool?
        let hide_weekly_quota: Bool?
        let has_quota_allocation: Bool?
        let overage_balance: WalletDecimalValue?
        let overage_balance_cents: WalletDecimalValue?
        let plan_name: String?
        let planName: String?
        let plan: String?
        let tier: String?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        for (id, name, period, reported, reset, hidden) in [
            ("devin.daily", "每日额度", QuotaPeriod.other, reply.daily_percentage?.amount, reply.daily_reset_at?.date, reply.hide_daily_quota),
            ("devin.weekly", "每周额度", .weekly, reply.weekly_percentage?.amount, reply.weekly_reset_at?.date, reply.hide_weekly_quota)
        ] {
            guard let reported else { continue }
            guard reported >= 0, reported <= 100 else { throw RefreshFailure.unreadableResponse }
            guard reply.has_quota_allocation != false, hidden != true else { continue }
            windows.append(QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: reported == 100,
                usedPercentage: NSDecimalNumber(decimal: reported).doubleValue, remainingCount: nil, totalCount: nil, resetsAt: reset))
        }
        let balance = reply.overage_balance?.amount ?? reply.overage_balance_cents.map { $0.amount / 100 }
        if let balance {
            windows.append(QuotaWindow(id: "devin.overage", name: "超额使用余额", scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: WalletBalance(currency: "USD", total: balance)))
        }
        let hasHiddenFigure = (reply.hide_daily_quota == true && reply.daily_percentage != nil)
            || (reply.hide_weekly_quota == true && reply.weekly_percentage != nil)
        guard !windows.isEmpty || reply.has_quota_allocation == false || hasHiddenFigure else { throw RefreshFailure.unreadableResponse }
        let plan = [reply.plan_name, reply.planName, reply.plan, reply.tier].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        let status: String? = reply.has_quota_allocation == false ? "当前组织未分配套餐额度"
            : reply.hide_daily_quota == true && reply.hide_weekly_quota == true ? "套餐额度由服务隐藏"
                : reply.hide_daily_quota == true ? "每日额度由服务隐藏"
                    : reply.hide_weekly_quota == true ? "每周额度由服务隐藏" : nil
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: plan,
            walletCollectedAt: balance == nil ? nil : collectedAt, quotaStatusText: status)
    }
}
