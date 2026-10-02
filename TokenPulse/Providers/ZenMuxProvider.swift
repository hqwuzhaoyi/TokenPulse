import Foundation

struct ZenMuxProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .zenMux, credential.kind == .apiKey,
              let fingerprint = credential.apiKeySourceFingerprint,
              credential.metadata["sourceCredentialFingerprint"] == fingerprint else { throw RefreshFailure.invalidCredential }
        do {
            let data = try await fetch("subscription/detail", credential: credential)
            var snapshot = try Self.subscription(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.apiKeySourceFingerprint
            do {
                let balance = try await fetch("payg/balance", credential: credential)
                snapshot.windows.append(try Self.wallet(balance))
                snapshot.walletCollectedAt = now()
            } catch is CancellationError { throw CancellationError() }
            catch {
                snapshot.walletFailure = ProviderHTTP.refreshFailure(error) as? RefreshFailure ?? .server
            }
            guard !snapshot.windows.isEmpty else { throw snapshot.walletFailure ?? RefreshFailure.noQuotaWindows }
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func fetch(_ route: String, credential: ProviderCredentialEnvelope) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://zenmux.ai/api/v1/management/\(route)")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if response.statusCode == 401 || response.statusCode == 403 { throw RefreshFailure.managementKeyRequired }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let success: Bool
        let data: Payload?
    }
    private struct Subscription: Decodable {
        struct Plan: Decodable { let tier: String? }
        struct Lane: Decodable { let usage_percentage: Double?; let resets_at: String? }
        let plan: Plan?
        let quota_5_hour: Lane?
        let quota_7_day: Lane?
    }
    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                guard text.range(of: #"\A-?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
                      text.filter({ $0.isNumber }).count <= 38,
                      let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { throw RefreshFailure.unreadableResponse }
                value = number
            } else { value = try container.decode(Decimal.self) }
            guard !value.isNaN else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct Balance: Decodable {
        let currency: String
        let total_credits: Amount
    }

    static func subscription(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let envelope = try? JSONDecoder().decode(Envelope<Subscription>.self, from: data), envelope.success,
              let payload = envelope.data else { throw RefreshFailure.unreadableResponse }
        let named = [("zenmux.five_hour", "5 小时额度", QuotaPeriod.fiveHour, payload.quota_5_hour),
                     ("zenmux.seven_day", "每周额度", .weekly, payload.quota_7_day)]
        let windows = try named.compactMap { id, name, period, lane -> QuotaWindow? in
            guard let lane else { return nil }
            guard let percentage = lane.usage_percentage else { return nil }
            guard percentage.isFinite, percentage >= 0, (percentage * 100).isFinite else { throw RefreshFailure.unreadableResponse }
            let reset: Date?
            if let raw = lane.resets_at {
                guard let date = ProviderHTTP.isoDate(raw) else { throw RefreshFailure.unreadableResponse }
                reset = date
            } else { reset = nil }
            return QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: percentage >= 1,
                               usedPercentage: percentage * 100, remainingCount: nil, totalCount: nil, resetsAt: reset)
        }
        let plan = payload.plan?.tier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
                             providerPlanName: plan?.isEmpty == false ? plan?.capitalized : nil)
    }

    static func wallet(_ data: Data) throws -> QuotaWindow {
        guard let envelope = try? JSONDecoder().decode(Envelope<Balance>.self, from: data), envelope.success,
              let balance = envelope.data else { throw RefreshFailure.unreadableResponse }
        let currency = balance.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard currency.count == 3, currency.unicodeScalars.allSatisfy({ 65...90 ~= $0.value }) else { throw RefreshFailure.unreadableResponse }
        return QuotaWindow(id: "zenmux.wallet", name: "按量钱包余额", scope: nil, usedPercentage: nil,
                           remainingCount: nil, totalCount: nil, resetsAt: nil,
                           wallet: WalletBalance(currency: currency, total: balance.total_credits.value))
    }
}
