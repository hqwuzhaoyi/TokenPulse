import Foundation

enum WindsurfWebSession {
    static let origin = "https://windsurf.com"
    static let storageKeys = ["devin_session_token", "devin_auth1_token", "devin_account_id", "devin_primary_org_id"]

    static func credential(storage: [String: String], accountID: UUID, origin: String = WindsurfWebSession.origin) throws -> ProviderCredentialEnvelope {
        guard origin == Self.origin else { throw RefreshFailure.invalidCredential }
        func value(_ key: String) throws -> String {
            guard let raw = storage[key], raw.utf8.count <= 65_536 else { throw RefreshFailure.invalidCredential }
            let value = ((try? JSONDecoder().decode(String.self, from: Data(raw.utf8))) ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard validHeader(value) else { throw RefreshFailure.invalidCredential }
            return value
        }
        return try WebProviderSession.credential(provider: .windsurf, origin: origin, accountID: accountID,
            accessToken: value("devin_session_token"), remoteAccountID: value("devin_account_id"),
            metadata: ["auth1Token": value("devin_auth1_token"), "organizationID": value("devin_primary_org_id")])
    }
    static func validHeader(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 65_536 && value.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
            && !value.contains("\"") && !value.contains("\\")
    }
}

/// Bounded unary protobuf handling: checked varints, legal field ids and complete payload consumption.
enum WindsurfProto {
    struct Field { let number: Int; let integer: UInt64?; let data: Data? }
    static func fields(_ data: Data) throws -> [Field] {
        guard data.count <= 1_048_576 else { throw RefreshFailure.unreadableResponse }
        let bytes = [UInt8](data)
        var index = 0
        var fields: [Field] = []
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for position in 0..<10 {
                guard index < bytes.count else { throw RefreshFailure.unreadableResponse }
                let byte = bytes[index]; index += 1
                if position == 9, byte > 1 { throw RefreshFailure.unreadableResponse }
                value |= UInt64(byte & 127) << (position * 7)
                if byte & 128 == 0 { return value }
            }
            throw RefreshFailure.unreadableResponse
        }
        while index < bytes.count {
            guard fields.count < 4096 else { throw RefreshFailure.unreadableResponse }
            let tag = try varint(), number = tag >> 3
            guard number > 0, number <= 536_870_911, let fieldNumber = Int(exactly: number) else { throw RefreshFailure.unreadableResponse }
            switch tag & 7 {
            case 0: fields.append(Field(number: fieldNumber, integer: try varint(), data: nil))
            case 1, 5:
                let width = tag & 7 == 1 ? 8 : 4
                guard bytes.count - index >= width else { throw RefreshFailure.unreadableResponse }
                index += width
                fields.append(Field(number: fieldNumber, integer: nil, data: nil))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - index), let count = Int(exactly: length) else { throw RefreshFailure.unreadableResponse }
                let payload = Data(bytes[index..<index + count]); index += count
                fields.append(Field(number: fieldNumber, integer: nil, data: payload))
            default: throw RefreshFailure.unreadableResponse
            }
        }
        return fields
    }
    static func append(_ value: UInt64, to data: inout Data) {
        var value = value
        while value > 127 { data.append(UInt8(value & 127) | 128); value >>= 7 }
        data.append(UInt8(value))
    }
    static func bytes(_ value: Data, field: UInt64, to data: inout Data) {
        append(field << 3 | 2, to: &data); append(UInt64(value.count), to: &data); data.append(value)
    }
}

struct WindsurfProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .windsurf, accountID: accountID, origins: [WindsurfWebSession.origin], now: now())
        guard let auth1 = credential.metadata["auth1Token"], let remote = credential.accountID,
              let org = credential.metadata["organizationID"], [credential.accessToken, auth1, remote, org].allSatisfy(WindsurfWebSession.validHeader) else {
            throw RefreshFailure.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        for (name, value) in ["Content-Type": "application/proto", "Accept": "application/proto", "Connect-Protocol-Version": "1",
                              "Origin": WindsurfWebSession.origin, "Referer": "https://windsurf.com/profile",
                              "x-auth-token": credential.accessToken, "x-devin-session-token": credential.accessToken,
                              "x-devin-auth1-token": auth1, "x-devin-account-id": remote, "x-devin-primary-org-id": org] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        var body = Data()
        WindsurfProto.bytes(Data(credential.accessToken.utf8), field: 1, to: &body)
        WindsurfProto.append(16, to: &body); WindsurfProto.append(1, to: &body)
        request.httpBody = body
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if 300..<400 ~= response.statusCode { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let envelope = try WindsurfProto.fields(data)
        let messages = envelope.filter { $0.number == 1 }
        guard messages.count == 1, let payload = messages.first?.data else { throw RefreshFailure.unreadableResponse }
        let fields = try WindsurfProto.fields(payload)
        var remaining: [Int: UInt64] = [:], resets: [Int: UInt64] = [:]
        var plan: String?
        for field in fields {
            switch field.number {
            case 1:
                guard let bytes = field.data else { throw RefreshFailure.unreadableResponse }
                let names = try WindsurfProto.fields(bytes).filter { $0.number == 2 }
                guard names.count <= 1 else { throw RefreshFailure.unreadableResponse }
                if let name = names.first {
                    guard let bytes = name.data, let decoded = String(data: bytes, encoding: .utf8) else { throw RefreshFailure.unreadableResponse }
                    let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                    plan = trimmed.isEmpty ? nil : String(trimmed.prefix(80))
                }
            case 14, 15:
                guard let value = field.integer, value <= 100, remaining[field.number] == nil else { throw RefreshFailure.unreadableResponse }
                remaining[field.number] = value
            case 17, 18:
                guard let value = field.integer, value <= 253_402_300_799, resets[field.number] == nil else { throw RefreshFailure.unreadableResponse }
                resets[field.number] = value
            default: break
            }
        }
        let windows = [("windsurf.daily", "每日额度", QuotaPeriod.other, 14, 17),
                       ("windsurf.weekly", "每周额度", .weekly, 15, 18)].compactMap { id, name, period, usedField, resetField -> QuotaWindow? in
            guard let left = remaining[usedField] else { return nil } // Absent is unknown, not an exhausted quota.
            return QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: left == 0,
                usedPercentage: Double(100 - left), remainingCount: nil, totalCount: nil,
                resetsAt: resets[resetField].flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0)) : nil })
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: plan)
    }
}
