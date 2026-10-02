import Foundation

/// A bounded, direct key query shared by the small hosted quota clients.
enum KeyQuotaRequest {
    static func fetch(provider: Provider, endpoint: String, accountID: UUID,
                      credential: ProviderCredentialEnvelope, transport: any ProviderTransport,
                      now: @Sendable () -> Date, body: Data? = nil,
                      parse: (Data, UUID, Date) throws -> QuotaSnapshot) async throws -> ProviderQueryResult {
        guard credential.provider == provider, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let snapshot = try parse(data, accountID, now())
            guard !snapshot.windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw RefreshFailure.unreadableResponse }
    }

    static func date(_ text: String?) -> Date? {
        guard let date = ProviderHTTP.isoDate(text),
              Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded()) != nil else { return nil }
        return date
    }
}

struct ClinePassProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Limit: Decodable {
            let type: String?
            let percentUsed: Double?
            let resetsAt: String?
        }
        struct Payload: Decodable { let limits: [Limit] }
        let success: Bool
        let data: Payload
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await KeyQuotaRequest.fetch(provider: .clinePass,
            endpoint: "https://api.cline.bot/api/v1/users/me/plan/usage-limits", accountID: accountID,
            credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        guard reply.success else { throw RefreshFailure.server }
        let definitions: [(String, String, QuotaPeriod)] = [
            ("five_hour", "5 小时额度", .fiveHour), ("weekly", "每周额度", .weekly),
            ("monthly", "每月额度", .monthly),
        ]
        let windows = try definitions.compactMap { type, name, period -> QuotaWindow? in
            let matches = reply.data.limits.filter { $0.type == type }
            guard matches.count <= 1 else { throw RefreshFailure.unreadableResponse }
            guard let item = matches.first, let percent = item.percentUsed,
                  percent.isFinite, percent >= 0 else { return nil }
            return QuotaWindow(id: "clinePass.\(type)", name: name, scope: nil, period: period,
                usedPercentage: percent, remainingCount: nil, totalCount: nil,
                resetsAt: KeyQuotaRequest.date(item.resetsAt))
        }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
