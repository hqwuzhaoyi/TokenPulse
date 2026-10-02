import Foundation

/// ZeroGPU GPU-seconds only. No inference bill, prepaid wallet, or model-token request.
struct HuggingFaceProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        enum Timestamp: Decodable {
            case iso(String), epoch(Double)
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .iso(text) }
                else { self = .epoch(try container.decode(Double.self)) }
            }
            var date: Date? {
                switch self {
                case .iso(let value): ProviderHTTP.isoDate(value)
                case .epoch(let value): value.isFinite && value > 0 && Int64(exactly: (value * 1000).rounded()) != nil
                    ? Date(timeIntervalSince1970: value) : nil
                }
            }
        }
        let base: Double?
        let current: Double?
        let resetsAt: Timestamp?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .huggingFace, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://huggingface.co/api/spaces/zero-gpu/quota")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return .init(snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard let total = reply.base, total.isFinite, total > 0,
              let remaining = reply.current, remaining.isFinite, remaining >= 0 else { throw RefreshFailure.noQuotaWindows }
        let percentage = max(0, total - remaining) / total * 100
        guard percentage.isFinite else { throw RefreshFailure.unreadableResponse }
        return QuotaSnapshot(accountID: accountID, windows: [
            QuotaWindow(id: "huggingFace.zeroGPU", name: "GPU 时长额度", scope: "ZeroGPU", isExhausted: remaining == 0,
                        usedPercentage: percentage, remainingCount: remaining, totalCount: total,
                        resetsAt: reply.resetsAt?.date, unit: "GPU 秒")
        ], collectedAt: collectedAt)
    }
}
