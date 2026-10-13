import Foundation

struct XiaomiCodingPlanProviderClient: Sendable {
    static let origin = "https://platform.xiaomimimo.com"
    static let loginURL = URL(string: origin + "/#/console/balance")!
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["platform.xiaomimimo.com", "xiaomimimo.com"], path: "/api/v1/",
        names: ["api-platform_serviceToken", "userId", "api-platform_ph", "api-platform_slh"],
        requiredNames: ["api-platform_serviceToken", "userId"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    static func credential(cookies: [HTTPCookie], accountID: UUID, now: Date) throws -> String {
        try WebProviderSession.cookieCredential(cookies: cookies, policy: cookiePolicy,
            provider: .xiaomiCodingPlan, origin: origin, accountID: accountID, now: now).encoded()
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        let date = now()
        try WebProviderSession.validate(credential, provider: .xiaomiCodingPlan, accountID: accountID, origins: [Self.origin], now: date)
        _ = try Self.cookiePolicy.values(in: credential.accessToken)
        do {
            async let usage = outcome("tokenPlan/usage", credential: credential)
            async let detail = outcome("tokenPlan/detail", credential: credential)
            async let balance = outcome("balance", credential: credential)
            let responses = try await (usage, detail, balance)
            // Expired authentication from any console route is not a missing
            // plan or missing optional amount. Preserve the old entire reading.
            for response in [responses.0, responses.1, responses.2] {
                if case .failure(.invalidCredential) = response { throw RefreshFailure.invalidCredential }
            }
            let usageData = try responses.0.get()
            let detailData = try? responses.1.get()
            var snapshot = try Self.snapshot(usage: usageData, detail: detailData, balance: nil,
                                             accountID: accountID, collectedAt: date)
            do {
                let balanceData = try responses.2.get()
                snapshot.windows.append(try Self.balanceWindow(balanceData))
                snapshot.walletCollectedAt = date
            } catch {
                snapshot.walletFailure = error as? RefreshFailure ?? .unreadableResponse
            }
            snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func outcome(_ path: String, credential: ProviderCredentialEnvelope) async throws -> Result<Data, RefreshFailure> {
        do {
            var request = URLRequest(url: URL(string: Self.origin + "/api/v1/" + path)!)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.setValue(credential.accessToken, forHTTPHeaderField: "Cookie")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue(Self.origin, forHTTPHeaderField: "Origin")
            request.setValue(Self.loginURL.absoluteString, forHTTPHeaderField: "Referer")
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let envelope = try Self.decode(Envelope<Empty>.self, data: data)
            try Self.check(envelope.code)
            return .success(data)
        } catch is CancellationError { throw CancellationError() }
        catch { return .failure(ProviderHTTP.refreshFailure(error) as? RefreshFailure ?? .network) }
    }

    private struct Empty: Decodable {}
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Usage: Decodable {
        struct Month: Decodable { let items: [Bucket] }
        struct Bucket: Decodable { let name: String?; let used: WalletNumericDecimal?; let limit: WalletNumericDecimal? }
        let monthUsage: Month
    }
    private struct Detail: Decodable { let planCode: String?; let currentPeriodEnd: String?; let expired: Bool? }
    private struct Balance: Decodable {
        let balance: WalletDecimalValue
        let currency: String
        let cashBalance: WalletDecimalValue?
        let giftBalance: WalletDecimalValue?
    }

    static func snapshot(usage: Data, detail: Data?, balance: Data?, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let payload = try decode(Envelope<Usage>.self, data: usage)
        try check(payload.code)
        guard let month = payload.data?.monthUsage else { throw RefreshFailure.unreadableResponse }
        let detailData = try detail.map { try decode(Envelope<Detail>.self, data: $0) }
        if let detailData { try check(detailData.code) }
        let plan = detailData?.data
        let reset = plan?.currentPeriodEnd.flatMap(date)
        var windows: [QuotaWindow] = []
        if plan?.expired != true {
            for (index, bucket) in month.items.enumerated() {
                guard let used = bucket.used?.amount, let total = bucket.limit?.amount,
                      used >= 0, total >= 0 else { throw RefreshFailure.unreadableResponse }
                guard total > 0 else { continue }
                let percentage = try WalletDecimalArithmetic.percentage(used: used, total: total)
                windows.append(.init(id: "xiaomi.plan.\(index)", name: bucket.name ?? "月度 Token 额度", scope: nil, period: .monthly,
                    isExhausted: used >= total, usedPercentage: percentage,
                    remainingCount: nil, totalCount: nil, resetsAt: reset, unit: "tokens",
                    exactCounts: .init(used: used, remaining: max(total - used, 0), total: total),
                    presentationLabel: bucket.name == nil ? .monthlyTokenAllowance : nil))
            }
        }
        if let balance { windows.append(try balanceWindow(balance)) }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
                     providerPlanName: plan?.planCode, walletCollectedAt: balance == nil ? nil : collectedAt,
                     quotaStatusText: plan?.expired == true || month.items.isEmpty || windows.allSatisfy { $0.wallet != nil } ? "没有当前 Coding Plan；余额与套餐额度分开显示" : nil)
    }

    static func balanceWindow(_ data: Data) throws -> QuotaWindow {
        let reply = try decode(Envelope<Balance>.self, data: data)
        try check(reply.code)
        guard let body = reply.data else { throw RefreshFailure.unreadableResponse }
        let currency = body.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currency.isEmpty else { throw RefreshFailure.unreadableResponse }
        return WalletExpansionHTTP.walletWindow(id: "xiaomi.wallet.\(currency)", wallet: .init(currency: currency,
            total: body.balance.amount, granted: body.giftBalance?.amount, toppedUp: body.cashBalance?.amount))
    }

    private static func check(_ code: Int) throws {
        switch code {
        case 0: return
        case 401, 403: throw RefreshFailure.invalidCredential
        case 429: throw RefreshFailure.rateLimited
        default: throw RefreshFailure.server
        }
    }
    private static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw RefreshFailure.unreadableResponse }
        return value
    }
    private static func date(_ text: String) -> Date? {
        if let date = ProviderHTTP.isoDate(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        guard let result = formatter.date(from: text), formatter.string(from: result) == text else { return nil }
        return result
    }
}
