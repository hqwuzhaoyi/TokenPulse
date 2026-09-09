import Foundation

struct OpenCodeGoProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Window: Decodable {
            let status: String?
            let percent: Double?
            let resetsAt: String?
        }
        struct Usage: Decodable {
            let rolling: Window?
            let weekly: Window?
            let monthly: Window?
        }
        let usage: Usage?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if response.statusCode == 403 { throw RefreshFailure.subscriptionRequired }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let windows = try Self.windows(data)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return ProviderQueryResult(
                snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func windows(_ data: Data) throws -> [QuotaWindow] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RefreshFailure.unreadableResponse
        }
        guard let usage = reply.usage else { return [] }
        return [
            window(usage.rolling, id: "opencode-go.rolling", name: "5 小时额度", period: .fiveHour),
            window(usage.weekly, id: "opencode-go.weekly", name: "每周额度", period: .weekly),
            window(usage.monthly, id: "opencode-go.monthly", name: "每月额度", period: .monthly),
        ].compactMap { $0 }
    }

    private static func window(_ value: Reply.Window?,
                               id: String,
                               name: String,
                               period: QuotaPeriod) -> QuotaWindow? {
        guard let value, let percent = value.percent else { return nil }
        let resetsAt = value.resetsAt.flatMap(ProviderHTTP.isoDate)
        return QuotaWindow(
            id: id,
            name: name,
            scope: nil,
            period: period,
            isExhausted: value.status?.lowercased() == "rate-limited",
            usedPercentage: min(max(percent, 0), 100),
            remainingCount: nil,
            totalCount: nil,
            resetsAt: resetsAt,
            cycleID: ProviderHTTP.cycleID(prefix: id, resetsAt: resetsAt)
        )
    }
}
