import Foundation

struct ElevenLabsProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        let character_count: Double?
        let character_limit: Double?
        let next_character_count_reset_unix: Double?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .elevenLabs, credential.kind == .apiKey else {
            throw RefreshFailure.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(credential.accessToken, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if [401, 403].contains(response.statusCode),
               let root = try? ProviderHTTP.json(data),
               let detail = root["detail"] as? [String: Any],
               detail["status"] as? String == "missing_permissions" {
                throw RefreshFailure.insufficientPermissions
            }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let windows = try Self.windows(data)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()),
                         updatedCredential: nil)
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func windows(_ data: Data) throws -> [QuotaWindow] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RefreshFailure.unreadableResponse
        }
        guard let used = reply.character_count, used.isFinite, used >= 0,
              let limit = reply.character_limit, limit.isFinite, limit > 0 else { return [] }
        let percentage = used / limit * 100
        guard percentage.isFinite else { return [] }
        let reset = reply.next_character_count_reset_unix.flatMap { value in
            value.isFinite && value > 0 && Int64(exactly: (value * 1000).rounded()) != nil
                ? Date(timeIntervalSince1970: value) : nil
        }
        // The response names a reset, not the length of the billing cycle.
        return [QuotaWindow(id: "elevenlabs.characters", name: "账期字符额度", scope: nil,
                            isExhausted: used >= limit, usedPercentage: percentage,
                            remainingCount: max(0, limit - used), totalCount: limit,
                            resetsAt: reset, unit: "字符")]
    }
}
