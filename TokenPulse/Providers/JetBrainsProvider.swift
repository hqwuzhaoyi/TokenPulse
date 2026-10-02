import Foundation
import CryptoKit

struct JetBrainsTokenTransfer: Decodable, Sendable {
    struct Access: Decodable, Sendable { let type: String; let license_id: String?; let org_id: String?; let workspace_id: String? }
    let version: Int
    let refresh_token: String
    let environment: String
    let server_url: String?
    let ai_access: Access
    let eap_tos_accepted: Bool
    var grantMarker: String { JetBrainsCredential.hash(["jetbrains.export.refresh.v1", refresh_token]) }
    static func decode(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 65_536, text.hasPrefix("central-"),
              let data = Data(base64Encoded: String(text.dropFirst(8))), data.count <= 49_152,
              let transfer = try? JSONDecoder().decode(Self.self, from: data), transfer.version == 1,
              transfer.environment == "prod", transfer.server_url == nil || transfer.server_url == "",
              transfer.ai_access.type == "license", transfer.ai_access.org_id == nil || transfer.ai_access.org_id == "",
              transfer.ai_access.workspace_id == nil || transfer.ai_access.workspace_id == "",
              let license = transfer.ai_access.license_id, JetBrainsCredential.safe(license), license.utf8.count <= 1_024,
              transfer.eap_tos_accepted, JetBrainsCredential.safe(transfer.refresh_token) else { throw RefreshFailure.invalidCredential }
        return transfer
    }
}

enum JetBrainsCredential {
    static let issuer = "https://oauth.account.jetbrains.com"
    static func safe(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32_768 && value.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
    static func hash(_ values: [String]) -> String {
        SHA256.hash(data: (try? JSONEncoder().encode(values)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    static func candidateRecordID(accountID: UUID, marker: String) -> UUID {
        let text = Array(hash(["jetbrains.candidate.v1", accountID.uuidString, marker]).prefix(32))
        let formatted = String(text[0..<8]) + "-" + String(text[8..<12]) + "-" + String(text[12..<16]) + "-" + String(text[16..<20]) + "-" + String(text[20..<32])
        return UUID(uuidString: formatted)!
    }
    static func fingerprint(_ envelope: ProviderCredentialEnvelope) throws -> String {
        guard envelope.provider == .jetBrainsAI, envelope.kind == .oauth, envelope.metadata["jetbrainsFormat"] == "device-v1",
              envelope.metadata["issuer"] == issuer, let local = envelope.metadata["localAccountID"], UUID(uuidString: local) != nil,
              let subject = envelope.accountID, safe(subject), let license = envelope.metadata["licenseID"], safe(license) else { throw RefreshFailure.invalidCredential }
        return hash(["jetbrains.license.v1", issuer, local, subject, license])
    }
    static func validateLocal(_ envelope: ProviderCredentialEnvelope, accountID: UUID, deviceID: String) throws {
        guard envelope.metadata["localAccountID"] == accountID.uuidString, envelope.metadata["ownerDeviceID"] == deviceID,
              envelope.metadata["credentialDistribution"] == "deviceLocal", envelope.metadata["clientID"] == "central-cli",
              envelope.metadata["grantMarker"]?.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil,
              safe(envelope.accessToken), envelope.refreshToken.map(safe) == true,
              let expiry = envelope.expiresAt, expiry.timeIntervalSince1970.isFinite,
              try fingerprint(envelope) == envelope.metadata["sourceCredentialFingerprint"] else { throw RefreshFailure.invalidCredential }
    }
    /// Only used on ID tokens received directly from the fixed HTTPS refresh response, never export claims.
    static func identity(_ token: String) throws -> (String, Date) {
        guard safe(token) else { throw RefreshFailure.unreadableResponse }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts.contains(where: { $0.isEmpty }) else { throw RefreshFailure.unreadableResponse }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        struct Claims: Decodable { let sub: String?; let jba_login: String?; let exp: Double }
        guard let bytes = Data(base64Encoded: payload), bytes.count <= 16_384,
              let claims = try? JSONDecoder().decode(Claims.self, from: bytes), claims.exp.isFinite,
              claims.exp > 0, claims.exp <= 32_503_680_000 else { throw RefreshFailure.unreadableResponse }
        guard let raw = claims.sub ?? claims.jba_login, safe(raw), raw.utf8.count <= 1_000 else { throw RefreshFailure.unreadableResponse }
        let subject = (claims.sub == nil ? "jba_login:" : "sub:") + raw
        return (subject, Date(timeIntervalSince1970: claims.exp))
    }
}

struct JetBrainsProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    var deviceID: String = DeviceOAuthIdentity.id

    struct JBAMint: Decodable { let access_token: String; let id_token: String; let refresh_token: String? }
    struct AIMint: Decodable { let token: String; let expiresAt: Int64? }

    func refreshJBA(_ envelope: ProviderCredentialEnvelope) async throws -> JBAMint {
        guard let refresh = envelope.refreshToken, JetBrainsCredential.safe(refresh) else { throw RefreshFailure.invalidCredential }
        let data = try await send(JetBrainsCredential.issuer + "/oauth2/token", body: ProviderHTTP.formBody([
            "grant_type": "refresh_token", "client_id": "central-cli", "refresh_token": refresh]), contentType: "application/x-www-form-urlencoded")
        guard let result = try? JSONDecoder().decode(JBAMint.self, from: data), JetBrainsCredential.safe(result.access_token),
              JetBrainsCredential.safe(result.id_token), result.refresh_token.map(JetBrainsCredential.safe) != false else { throw RefreshFailure.unreadableResponse }
        return result
    }
    func provide(_ envelope: ProviderCredentialEnvelope) async throws -> AIMint {
        guard let access = envelope.metadata["jbaAccessToken"], JetBrainsCredential.safe(access),
              let license = envelope.metadata["licenseID"], JetBrainsCredential.safe(license) else { throw RefreshFailure.invalidCredential }
        _ = try await send("https://auth.grazie.ai/auth/jetbrains-jwt/register", body: Data("{}".utf8), bearer: access, accepted: [200, 201])
        let data = try await send("https://auth.grazie.ai/auth/jetbrains-jwt/provide-access/license/v2",
            body: JSONEncoder().encode(["licenseId": license]), bearer: access)
        guard let result = try? JSONDecoder().decode(AIMint.self, from: data), JetBrainsCredential.safe(result.token) else { throw RefreshFailure.unreadableResponse }
        return result
    }
    func refreshAI(_ envelope: ProviderCredentialEnvelope) async throws -> AIMint {
        let data = try await send("https://api.jetbrains.ai/user/v5/auth/jwt/refresh/v3", body: nil, aiToken: envelope.accessToken)
        guard let result = try? JSONDecoder().decode(AIMint.self, from: data), JetBrainsCredential.safe(result.token) else { throw RefreshFailure.unreadableResponse }
        return result
    }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try JetBrainsCredential.validateLocal(credential, accountID: accountID, deviceID: deviceID)
        guard credential.metadata["stage"] == "ready", credential.expiresAt! > now() else { throw RefreshFailure.invalidCredential }
        let quota = try await send("https://api.jetbrains.ai/user/v5/quota/get", body: nil, aiToken: credential.accessToken)
        let refill = try await send("https://api.jetbrains.ai/user/v5/quota/metadata/refill", body: nil, aiToken: credential.accessToken)
        var snapshot = try JetBrainsQuotaParser.snapshot(quota, refill: refill, accountID: accountID, collectedAt: now())
        snapshot.sourceCredentialFingerprint = try JetBrainsCredential.fingerprint(credential)
        return .init(snapshot: snapshot, updatedCredential: nil)
    }
    private func send(_ path: String, body: Data?, contentType: String = "application/json", bearer: String? = nil,
                      aiToken: String? = nil, accepted: Set<Int> = [200]) async throws -> Data {
        var request = URLRequest(url: URL(string: path)!)
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let aiToken { request.setValue(aiToken, forHTTPHeaderField: "Grazie-Authenticate-JWT") }
        // Attribute this app accurately; no new OAuth login or copied CLI secret is used.
        if bearer != nil || aiToken != nil { request.setValue("TokenPulse/1.0", forHTTPHeaderField: "Grazie-Agent") }
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url == request.url else { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        guard accepted.contains(response.statusCode), data.count <= 1_000_000 else { throw RefreshFailure.unreadableResponse }
        return data
    }
}

/// Each device owns a separate export lineage. Persist before any possibly rotating POST.
actor JetBrainsSessionCoordinator {
    static let shared = JetBrainsSessionCoordinator()
    private struct Flight { let attemptID: UUID?; let task: Task<(String, QuotaSnapshot), Error> }
    private var flights: [String: Flight] = [:]
    private var attemptRecords: [UUID: UUID] = [:]
    func cancelImport(accountID: UUID, vault: DeviceOAuthCredentialVault, attemptID: UUID) async throws {
        guard let recordID = attemptRecords[attemptID], recordID != accountID else { return }
        let key = vault.deviceID + "/" + recordID.uuidString
        if let flight = flights[key] {
            guard flight.attemptID == attemptID else { return }
            flight.task.cancel()
        }
        let version = try await vault.version(for: recordID)
        guard let text = version.credential,
              let envelope = try? ProviderCredentialEnvelope.decode(text, expectedProvider: .jetBrainsAI),
              envelope.metadata["importAttemptID"] == attemptID.uuidString else { return }
        _ = try await vault.compareAndSwap(expectedGeneration: version.generation, credential: nil, for: recordID)
        attemptRecords[attemptID] = nil
    }
    func importTransfer(_ input: String, accountID: UUID, vault: DeviceOAuthCredentialVault,
                        expectedIdentity: String? = nil, attemptID: UUID = UUID(), transport: any ProviderTransport = URLSessionProviderTransport.rejectingRedirects(),
                        now: @escaping @Sendable () -> Date = Date.init) async throws -> String {
        let transfer = try JetBrainsTokenTransfer.decode(input)
        let active = try await vault.version(for: accountID)
        let activeEnvelope = try active.credential.map { try ProviderCredentialEnvelope.decode($0, expectedProvider: .jetBrainsAI) }
        let recordID = activeEnvelope?.metadata["grantMarker"] == transfer.grantMarker ? accountID
            : JetBrainsCredential.candidateRecordID(accountID: accountID, marker: transfer.grantMarker)
        attemptRecords[attemptID] = recordID
        let key = vault.deviceID + "/" + recordID.uuidString
        guard flights[key] == nil else { throw RefreshFailure.server }
        let task = Task { try await Self.perform(accountID: accountID, vault: vault, transfer: transfer,
            recordID: recordID, activeBaseline: active.generation, expectedIdentity: expectedIdentity,
            importAttemptID: recordID == accountID ? nil : attemptID, transport: transport, now: now) }
        flights[key] = Flight(attemptID: attemptID, task: task); defer { flights[key] = nil }
        return try await task.value.0
    }
    func quota(accountID: UUID, vault: DeviceOAuthCredentialVault, transport: any ProviderTransport,
               now: @escaping @Sendable () -> Date) async throws -> QuotaSnapshot {
        let key = vault.deviceID + "/" + accountID.uuidString
        if let flight = flights[key] { return try await flight.task.value.1 }
        let task = Task { try await Self.perform(accountID: accountID, vault: vault, transfer: nil,
            recordID: accountID, activeBaseline: nil, expectedIdentity: nil, importAttemptID: nil, transport: transport, now: now) }
        flights[key] = Flight(attemptID: nil, task: task); defer { flights[key] = nil }
        return try await task.value.1
    }
    private static func perform(accountID: UUID, vault: DeviceOAuthCredentialVault, transfer: JetBrainsTokenTransfer?,
                                recordID: UUID, activeBaseline: UInt64?,
                                expectedIdentity: String?, importAttemptID: UUID?, transport: any ProviderTransport,
                                now: @escaping @Sendable () -> Date) async throws -> (String, QuotaSnapshot) {
        var version = try await vault.version(for: recordID)
        var envelope = try version.credential.map { try ProviderCredentialEnvelope.decode($0, expectedProvider: .jetBrainsAI) }
        if let transfer {
            let fresh = try await vault.reserveGrantMarker(transfer.grantMarker, accountID: accountID)
            if envelope?.metadata["grantMarker"] != transfer.grantMarker {
                guard fresh else { throw RefreshFailure.invalidCredential }
                envelope = ProviderCredentialEnvelope(provider: .jetBrainsAI, kind: .oauth, accessToken: "not-issued",
                    refreshToken: transfer.refresh_token, metadata: ["jetbrainsFormat": "device-v1", "issuer": JetBrainsCredential.issuer,
                        "clientID": "central-cli", "credentialDistribution": "deviceLocal", "ownerDeviceID": vault.deviceID,
                        "localAccountID": accountID.uuidString, "licenseID": transfer.ai_access.license_id!,
                        "grantMarker": transfer.grantMarker, "stage": "new"])
                envelope?.metadata["expectedIdentity"] = expectedIdentity
                envelope?.metadata["candidateDeadline"] = String(now().addingTimeInterval(3_600).timeIntervalSince1970)
            } else {
                guard envelope?.metadata["licenseID"] == transfer.ai_access.license_id else { throw RefreshFailure.invalidCredential }
            }
        }
        guard var session = envelope, session.metadata["localAccountID"] == accountID.uuidString,
              session.metadata["ownerDeviceID"] == vault.deviceID else { throw RefreshFailure.invalidCredential }
        if recordID != accountID {
            guard let text = session.metadata["candidateDeadline"], let deadline = Double(text), deadline.isFinite,
                  deadline > now().timeIntervalSince1970 else {
                try await vault.delete(for: recordID); throw RefreshFailure.invalidCredential
            }
            guard session.metadata["stage"] != "activationPending" else { throw RefreshFailure.invalidCredential }
        }
        let client = JetBrainsProviderClient(transport: transport, now: now, deviceID: vault.deviceID)
        func checkpoint(_ updated: ProviderCredentialEnvelope) async throws {
            try Task.checkCancellation()
            var tagged = updated
            if let importAttemptID { tagged.metadata["importAttemptID"] = importAttemptID.uuidString }
            if let expectedIdentity { tagged.metadata["expectedIdentity"] = expectedIdentity }
            guard let saved = try await vault.compareAndSwap(expectedGeneration: version.generation, credential: tagged.encoded(), for: recordID) else { throw CancellationError() }
            version = saved; session = tagged
        }
        if recordID != accountID, importAttemptID != nil, session.metadata["stage"] != "new" {
            // Claim a resumed candidate before its first network await; an old page cannot clear it.
            try await checkpoint(session)
        }
        func jba() async throws {
            guard !["oauthPending", "uncertain", "terminal"].contains(session.metadata["stage"] ?? "") else { throw RefreshFailure.invalidCredential }
            var pending = session; pending.metadata["stage"] = "oauthPending"
            try await checkpoint(pending)
            do {
                let mint = try await client.refreshJBA(session)
                var issued = session; issued.refreshToken = mint.refresh_token ?? session.refreshToken
                issued.metadata["jbaAccessToken"] = mint.access_token; issued.metadata["mintedIDToken"] = mint.id_token
                issued.metadata["stage"] = "identityPending"
                // Preserve a returned refresh replacement even if later identity parsing or signing fails.
                try await checkpoint(issued)
            } catch {
                var uncertain = session; uncertain.metadata["stage"] = error as? RefreshFailure == .invalidCredential ? "terminal" : "uncertain"
                try await checkpoint(uncertain); throw error
            }
        }
        func verifyMint() async throws {
            guard let token = session.metadata["mintedIDToken"] else { throw RefreshFailure.invalidCredential }
            let (subject, expiry) = try JetBrainsCredential.identity(token)
            guard expiry > now(), session.accountID == nil || session.accountID == subject else { throw RefreshFailure.invalidCredential }
            var verified = session; verified.accountID = subject
            verified.metadata["jbaExpiresAt"] = String(expiry.timeIntervalSince1970); verified.metadata["stage"] = "jbaReady"
            verified.metadata["sourceCredentialFingerprint"] = try JetBrainsCredential.fingerprint(verified)
            if let expected = expectedIdentity ?? session.metadata["expectedIdentity"], verified.metadata["sourceCredentialFingerprint"] != expected { throw RefreshFailure.invalidCredential }
            try await checkpoint(verified)
        }
        func provision() async throws {
            let jbaExpiry = Double(session.metadata["jbaExpiresAt"] ?? "").map(Date.init(timeIntervalSince1970:))
            if session.metadata["stage"] == "new" || jbaExpiry.map({ $0 <= now() }) != false {
                try await jba(); try await verifyMint()
            } else if session.metadata["stage"] == "identityPending" { try await verifyMint() }
            guard session.metadata["stage"] == "jbaReady" || session.metadata["stage"] == "ready" || session.metadata["stage"] == "aiPending" else { throw RefreshFailure.invalidCredential }
            var preparing = session; preparing.metadata["stage"] = "jbaReady"; try await checkpoint(preparing)
            let mint: JetBrainsProviderClient.AIMint
            do { mint = try await client.provide(session) }
            catch RefreshFailure.invalidCredential { try await jba(); try await verifyMint(); mint = try await client.provide(session) }
            var ready = session; ready.accessToken = mint.token
            guard mint.expiresAt.map({ $0 <= 32_503_680_000_000 }) != false else { throw RefreshFailure.unreadableResponse }
            ready.expiresAt = mint.expiresAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0) / 1_000) : nil } ?? now().addingTimeInterval(86_400)
            guard ready.expiresAt! > now() else { throw RefreshFailure.unreadableResponse }
            ready.metadata["stage"] = "ready"; try await checkpoint(ready)
        }
        if ["oauthPending", "uncertain", "terminal"].contains(session.metadata["stage"] ?? "") { throw RefreshFailure.invalidCredential }
        if session.metadata["stage"] == "identityPending" { try await verifyMint() }
        if session.metadata["stage"] != "ready" { try await provision() }
        else if session.expiresAt.map({ $0 <= now().addingTimeInterval(60) }) != false {
            let jbaExpiry = Double(session.metadata["jbaExpiresAt"] ?? "") ?? 0
            if jbaExpiry > now().timeIntervalSince1970 {
                var pending = session; pending.metadata["stage"] = "aiPending"; try await checkpoint(pending)
                do {
                    let mint = try await client.refreshAI(session)
                    var ready = session; ready.accessToken = mint.token; ready.expiresAt = now().addingTimeInterval(86_400)
                    ready.metadata["stage"] = "ready"; try await checkpoint(ready)
                } catch { try await provision() }
            } else { try await provision() }
        }
        try JetBrainsCredential.validateLocal(session, accountID: accountID, deviceID: vault.deviceID)
        if let expected = expectedIdentity ?? session.metadata["expectedIdentity"], try JetBrainsCredential.fingerprint(session) != expected { throw RefreshFailure.invalidCredential }
        let result: ProviderQueryResult
        do { result = try await client.quota(accountID: accountID, credential: session) }
        catch RefreshFailure.invalidCredential { try await provision(); result = try await client.quota(accountID: accountID, credential: session) }
        guard try await vault.version(for: recordID).generation == version.generation else { throw CancellationError() }
        if recordID != accountID {
            guard version.generation < UInt64.max, let activeBaseline else { throw RefreshFailure.invalidCredential }
            var receipt = session
            receipt.metadata["candidateRecordID"] = recordID.uuidString
            receipt.metadata["candidateGeneration"] = String(version.generation + 1)
            receipt.metadata["activeBaselineGeneration"] = String(activeBaseline)
            try await checkpoint(receipt)
        }
        return (try session.encoded(), result.snapshot)
    }
}

enum JetBrainsQuotaParser {
    struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let object = try? c.decode([String: WalletDecimalValue].self) {
                guard let amount = object["amount"]?.amount else { throw RefreshFailure.unreadableResponse }; value = amount
            } else { value = try c.decode(WalletDecimalValue.self).amount }
            guard value >= 0, !value.isNaN else { throw RefreshFailure.unreadableResponse }
        }
        func credits() throws -> Decimal {
            var input = value, scale = Decimal(100_000), result = Decimal(), inverse = Decimal()
            guard NSDecimalDivide(&result, &input, &scale, .plain) == .noError,
                  NSDecimalMultiply(&inverse, &result, &scale, .plain) == .noError, inverse == value else { throw RefreshFailure.unreadableResponse }
            return result
        }
    }
    struct Bucket: Decodable { let current: Amount?; let maximum: Amount?; let available: Amount? }
    struct Quota: Decodable { let current: Amount?; let maximum: Amount?; let tariffQuota: Bucket?; let topUpQuota: Bucket?; let until: Int64? }
    struct Reply: Decodable { let current: Quota }
    struct Refill: Decodable { struct Period: Decodable { let last: Int64; let next: Int64 }; let current: Period }
    static func snapshot(_ data: Data, refill: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard data.count <= 1_000_000, refill.count <= 1_000_000,
              let reply = try? JSONDecoder().decode(Reply.self, from: data), let period = try? JSONDecoder().decode(Refill.self, from: refill),
              period.current.last >= 0, period.current.next > period.current.last, period.current.next <= 32_503_680_000_000 else { throw RefreshFailure.unreadableResponse }
        let quota = reply.current, reset = Date(timeIntervalSince1970: Double(period.current.next) / 1_000)
        let cycle = String(period.current.last)
        var windows: [QuotaWindow] = []
        func append(_ bucket: Bucket, id: String, name: String, resetsAt: Date?) throws {
            let used = try bucket.current?.credits(), total = try bucket.maximum?.credits(), remaining = try bucket.available?.credits()
            guard used != nil || total != nil || remaining != nil else { return }
            let percentage = used.flatMap { u in total.flatMap { $0 > 0 ? NSDecimalNumber(decimal: u / $0 * 100).doubleValue : nil } }
            guard percentage?.isFinite != false else { throw RefreshFailure.unreadableResponse }
            windows.append(QuotaWindow(id: id, name: name, scope: nil, isExhausted: remaining.map { $0 == 0 },
                usedPercentage: percentage, remainingCount: remaining.map { NSDecimalNumber(decimal: $0).doubleValue },
                totalCount: total.map { NSDecimalNumber(decimal: $0).doubleValue }, resetsAt: resetsAt, cycleID: resetsAt == nil ? nil : cycle,
                unit: "AI credits",
                exactCounts: .init(used: used, remaining: remaining, total: total), resetSemantics: resetsAt == nil ? .nonResettingAllowance : nil))
        }
        if let tariff = quota.tariffQuota { try append(tariff, id: "jetbrains.tariff", name: "订阅额度", resetsAt: reset) }
        else { try append(.init(current: quota.current, maximum: quota.maximum, available: nil), id: "jetbrains.total", name: "AI 额度", resetsAt: reset) }
        if let topUp = quota.topUpQuota { try append(topUp, id: "jetbrains.topup", name: "额外额度", resetsAt: nil) }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
            quotaStatusText: windows.isEmpty ? "服务未提供可显示的额度池" : nil)
    }
}
