import Foundation
import CryptoKit

struct NousRemoteIdentity: Equatable, Sendable {
    let subject: String
    let organization: String
}

enum NousPortalCredential {
    static let portal = "https://portal.nousresearch.com"
    static let clientID = "hermes-cli" // Public native device-flow identifier in the official Hermes client.
    static let scope = "inference:invoke"
    static func safe(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 65_536 && value.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
    static func fingerprint(_ envelope: ProviderCredentialEnvelope) throws -> String {
        guard envelope.provider == .nousPortal, envelope.kind == .oauth,
              envelope.metadata["nousSessionFormat"] == "device-v1", envelope.metadata["portal"] == portal,
              let local = envelope.metadata["localAccountID"], let id = UUID(uuidString: local),
              let subject = envelope.accountID, safe(subject),
              let org = envelope.metadata["organizationID"], safe(org) else { throw RefreshFailure.invalidCredential }
        let data = try JSONEncoder().encode([Provider.nousPortal.rawValue, portal, id.uuidString, subject, org])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func validateLocal(_ envelope: ProviderCredentialEnvelope, accountID: UUID, deviceID: String) throws {
        guard envelope.metadata["localAccountID"] == accountID.uuidString,
              envelope.metadata["ownerDeviceID"] == deviceID,
              envelope.metadata["clientID"] == clientID, envelope.metadata["credentialDistribution"] == "deviceLocal",
              safe(envelope.accessToken), envelope.refreshToken.map(safe) != false,
              let expires = envelope.expiresAt, expires.timeIntervalSince1970.isFinite,
              try fingerprint(envelope) == envelope.metadata["sourceCredentialFingerprint"] else { throw RefreshFailure.invalidCredential }
    }
    static func identity(_ envelope: ProviderCredentialEnvelope) throws -> NousRemoteIdentity {
        _ = try fingerprint(envelope)
        return .init(subject: envelope.accountID!, organization: envelope.metadata["organizationID"]!)
    }
}

struct NousPortalProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    var deviceID: String = DeviceOAuthIdentity.id

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try NousPortalCredential.validateLocal(credential, accountID: accountID, deviceID: deviceID)
        guard credential.expiresAt.map({ $0 > now() }) == true else { throw RefreshFailure.invalidCredential }
        let data = try await account(accessToken: credential.accessToken)
        let remote = try Self.remoteIdentity(data)
        guard remote == (try NousPortalCredential.identity(credential)) else { throw RefreshFailure.invalidCredential }
        var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
        snapshot.sourceCredentialFingerprint = try NousPortalCredential.fingerprint(credential)
        return .init(snapshot: snapshot, updatedCredential: nil)
    }

    func account(accessToken: String) async throws -> Data {
        guard NousPortalCredential.safe(accessToken) else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: NousPortalCredential.portal + "/api/oauth/account")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if response.value(forHTTPHeaderField: "x-vercel-mitigated") != nil { throw RefreshFailure.rateLimited }
            if 300..<400 ~= response.statusCode { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return data
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Account: Decodable {
        struct User: Decodable { let privy_did: String? }
        struct Organization: Decodable { let id: String? }
        struct Subscription: Decodable {
            let plan: String?
            let monthly_credits: WalletDecimalValue?
            let credits_remaining: WalletDecimalValue?
            let rollover_credits: WalletDecimalValue?
            let current_period_end: String?
        }
        struct Access: Decodable {
            let organisation_id: String?
            let subscription_credits_remaining: WalletDecimalValue?
            let purchased_credits_remaining: WalletDecimalValue?
            let total_usable_credits: WalletDecimalValue?
            let allowed: Bool?
        }
        let user: User?
        let organisation: Organization?
        let subscription: Subscription?
        let purchased_credits_remaining: WalletDecimalValue?
        let paid_service_access: Access?
        let error: String?
    }
    private static func decode(_ data: Data) throws -> Account {
        guard let account = try? JSONDecoder().decode(Account.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard account.error == nil else { throw RefreshFailure.server }
        if let organization = account.organisation?.id, let paidOrganization = account.paid_service_access?.organisation_id,
           organization != paidOrganization { throw RefreshFailure.unreadableResponse }
        return account
    }
    static func remoteIdentity(_ data: Data) throws -> NousRemoteIdentity {
        let account = try decode(data)
        guard let subject = account.user?.privy_did, NousPortalCredential.safe(subject), subject.utf8.count <= 1024,
              let org = account.organisation?.id ?? account.paid_service_access?.organisation_id,
              NousPortalCredential.safe(org), org.utf8.count <= 1024 else { throw RefreshFailure.unreadableResponse }
        return .init(subject: subject, organization: org)
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let account = try decode(data)
        var windows: [QuotaWindow] = []
        let size = account.subscription?.monthly_credits?.amount
        let left = account.subscription?.credits_remaining?.amount ?? account.paid_service_access?.subscription_credits_remaining?.amount
        guard size.map({ $0 >= 0 }) != false else { throw RefreshFailure.unreadableResponse }
        if size.map({ $0 > 0 }) == true || left.map({ $0 > 0 }) == true {
            let used: Decimal?
            if let size, size > 0, let left { used = difference(size, max(left, 0)) } else { used = nil }
            let percentage = used.flatMap { used in
                size.flatMap { $0 > 0 ? NSDecimalNumber(decimal: used / $0 * 100).doubleValue : nil }
            }
            guard percentage.map(\.isFinite) != false else { throw RefreshFailure.unreadableResponse }
            let reset: Date?
            if let date = account.subscription?.current_period_end {
                guard let parsed = ProviderHTTP.isoDate(date) else { throw RefreshFailure.unreadableResponse }
                reset = parsed
            } else { reset = nil }
            windows.append(QuotaWindow(id: "nous.subscription", name: "订阅 credits", scope: nil, period: .monthly,
                isExhausted: size.map({ $0 > 0 }) == true ? left.map { $0 <= 0 } : nil,
                usedPercentage: percentage, remainingCount: nil, totalCount: nil,
                resetsAt: reset, unit: "credits", exactCounts: DecimalQuotaCounts(used: used, remaining: left, total: size),
                resetSemantics: reset == nil ? .nonResettingAllowance : nil))
        }
        let purchased = account.paid_service_access?.purchased_credits_remaining?.amount ?? account.purchased_credits_remaining?.amount
        if let purchased {
            windows.append(QuotaWindow(id: "nous.purchased", name: "购买 credits", scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "credits",
                exactCounts: DecimalQuotaCounts(remaining: purchased), resetSemantics: .nonResettingAllowance))
        }
        if let total = account.paid_service_access?.total_usable_credits?.amount {
            windows.append(QuotaWindow(id: "nous.total", name: "总可用 credits", scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: WalletBalance(currency: "credits", total: total, isMonetary: false)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
            providerPlanName: account.subscription?.plan, quotaStatusText: account.paid_service_access?.allowed == false ? "当前未开放付费服务" : nil)
    }
    private static func difference(_ size: Decimal, _ left: Decimal) -> Decimal? {
        guard left <= size else { return 0 }
        var size = size, left = left, used = Decimal(), inverse = Decimal()
        guard NSDecimalSubtract(&used, &size, &left, .plain) == .noError,
              NSDecimalSubtract(&inverse, &size, &used, .plain) == .noError, inverse == left else { return nil }
        return used
    }
}

struct NousPortalAuthenticator: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    var deviceID: String = DeviceOAuthIdentity.id
    private struct DeviceCode: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let verification_uri_complete: String?
        let expires_in: Double
        let interval: Double?
    }
    private struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let token_type: String?
        let scope: String?
    }
    func begin(accountID: UUID) async throws -> ProviderLoginSession {
        let (data, response) = try await post("device/code", form: ["client_id": NousPortalCredential.clientID, "scope": NousPortalCredential.scope])
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        guard let reply = try? JSONDecoder().decode(DeviceCode.self, from: data), reply.expires_in.isFinite, reply.expires_in > 0,
              NousPortalCredential.safe(reply.device_code), NousPortalCredential.safe(reply.user_code),
              let uri = URL(string: reply.verification_uri_complete ?? reply.verification_uri), Self.validVerification(uri),
              reply.interval.map({ $0.isFinite && $0 > 0 }) != false else { throw ProviderIntegrationError.unreadableResponse }
        return ProviderLoginSession(provider: .nousPortal, authorizationURL: uri, userCode: reply.user_code,
            deviceCode: reply.device_code, state: nil, codeVerifier: nil, callbackURL: nil,
            pollingInterval: max(reply.interval ?? 5, 1), expiresAt: now().addingTimeInterval(reply.expires_in),
            metadata: ["localAccountID": accountID.uuidString, "ownerDeviceID": deviceID])
    }
    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .nousPortal, session.metadata["ownerDeviceID"] == deviceID,
              let rawID = session.metadata["localAccountID"], let id = UUID(uuidString: rawID),
              let code = session.deviceCode, NousPortalCredential.safe(code) else { throw ProviderIntegrationError.invalidCredentialData }
        guard session.expiresAt.map({ $0 > now() }) == true else { throw ProviderIntegrationError.loginExpired }
        let (data, response) = try await post("token", form: ["grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                                                           "client_id": NousPortalCredential.clientID, "device_code": code])
        let error = (try? ProviderHTTP.json(data))?["error"] as? String
        if error == "authorization_pending" { return .pending(retryAfter: await NousDevicePollPacing.shared.interval(code: code, initial: session.pollingInterval ?? 5)) }
        if error == "slow_down" { return .pending(retryAfter: await NousDevicePollPacing.shared.slowDown(code: code, initial: session.pollingInterval ?? 5)) }
        if error == "expired_token" { throw ProviderIntegrationError.loginExpired }
        if error == "access_denied" { throw ProviderIntegrationError.invalidCredential }
        if response.statusCode == 429 || response.value(forHTTPHeaderField: "x-vercel-mitigated") != nil {
            return .pending(retryAfter: max(session.pollingInterval ?? 5, 10))
        }
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        var envelope = try tokens(data, accountID: id, identity: nil)
        let account = try await NousPortalProviderClient(transport: transport, now: now, deviceID: deviceID).account(accessToken: envelope.accessToken)
        let identity = try NousPortalProviderClient.remoteIdentity(account)
        envelope.accountID = identity.subject
        envelope.metadata["organizationID"] = identity.organization
        envelope.metadata["sourceCredentialFingerprint"] = try NousPortalCredential.fingerprint(envelope)
        await NousDevicePollPacing.shared.finished(code: code)
        return .completed(credential: try envelope.encoded())
    }
    func refresh(_ envelope: ProviderCredentialEnvelope, accountID: UUID) async throws -> ProviderCredentialEnvelope {
        guard let refresh = envelope.refreshToken, NousPortalCredential.safe(refresh) else { throw RefreshFailure.invalidCredential }
        let (data, response) = try await post("token", form: ["grant_type": "refresh_token", "client_id": NousPortalCredential.clientID], refreshToken: refresh)
        if response.value(forHTTPHeaderField: "x-vercel-mitigated") != nil { throw NousRefreshError.safeRejection(.rateLimited) }
        let error = (try? ProviderHTTP.json(data))?["error"] as? String
        if ["invalid_grant", "invalid_token", "refresh_token_reused", "access_denied"].contains(error ?? "") || [401, 403].contains(response.statusCode) {
            throw NousRefreshError.terminal
        }
        if response.statusCode == 429 { throw NousRefreshError.safeRejection(.rateLimited) }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        var updated = try tokens(data, accountID: accountID, identity: try NousPortalCredential.identity(envelope))
        guard updated.refreshToken != envelope.refreshToken else { throw RefreshFailure.unreadableResponse }
        updated.metadata["sourceCredentialFingerprint"] = try NousPortalCredential.fingerprint(updated)
        return updated
    }
    private func tokens(_ data: Data, accountID: UUID, identity: NousRemoteIdentity?) throws -> ProviderCredentialEnvelope {
        guard let token = try? JSONDecoder().decode(Tokens.self, from: data), NousPortalCredential.safe(token.access_token),
              NousPortalCredential.safe(token.refresh_token), token.expires_in.isFinite, token.expires_in > 0,
              token.token_type.map({ $0.lowercased() == "bearer" }) != false else { throw RefreshFailure.unreadableResponse }
        return ProviderCredentialEnvelope(provider: .nousPortal, kind: .oauth, accessToken: token.access_token,
            refreshToken: token.refresh_token, expiresAt: now().addingTimeInterval(token.expires_in), accountID: identity?.subject,
            metadata: ["nousSessionFormat": "device-v1", "portal": NousPortalCredential.portal, "clientID": NousPortalCredential.clientID,
                       "scope": token.scope ?? NousPortalCredential.scope, "localAccountID": accountID.uuidString, "ownerDeviceID": deviceID,
                       "credentialDistribution": "deviceLocal", "organizationID": identity?.organization ?? "",
                       "rotationState": "active", "issuedTTL": String(token.expires_in), "chainID": UUID().uuidString])
    }
    private func post(_ route: String, form: [String: String], refreshToken: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: NousPortalCredential.portal + "/api/oauth/" + route)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let refreshToken { request.setValue(refreshToken, forHTTPHeaderField: "x-nous-refresh-token") }
        request.httpBody = ProviderHTTP.formBody(form)
        return try await ProviderHTTP.send(request, transport: transport)
    }
    private static func validVerification(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return host == "nousresearch.com" || host.hasSuffix(".nousresearch.com")
    }
}

enum NousRefreshError: Error, Sendable { case safeRejection(RefreshFailure), terminal }

private actor NousDevicePollPacing {
    static let shared = NousDevicePollPacing()
    private var intervals: [String: TimeInterval] = [:]
    func interval(code: String, initial: TimeInterval) -> TimeInterval { intervals[code] ?? initial }
    func slowDown(code: String, initial: TimeInterval) -> TimeInterval {
        let value = min((intervals[code] ?? initial) + 5, 60)
        intervals[code] = value
        return value
    }
    func finished(code: String) { intervals[code] = nil }
}

/// One whole refresh/query operation per account/device. Only the vault performs atomic generation CAS.
actor NousSessionCoordinator {
    static let shared = NousSessionCoordinator()
    private var inFlight: [String: Task<QuotaSnapshot, Error>] = [:]
    func quota(accountID: UUID, vault: DeviceOAuthCredentialVault,
               transport: any ProviderTransport = URLSessionProviderTransport.rejectingRedirects(),
               now: @escaping @Sendable () -> Date = Date.init) async throws -> QuotaSnapshot {
        let key = vault.deviceID + "/" + accountID.uuidString
        if let task = inFlight[key] { return try await task.value }
        let task = Task { try await Self.perform(accountID: accountID, vault: vault, transport: transport, now: now) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
    private static func perform(accountID: UUID, vault: DeviceOAuthCredentialVault, transport: any ProviderTransport,
                                now: @escaping @Sendable () -> Date) async throws -> QuotaSnapshot {
        var version = try await vault.version(for: accountID)
        guard let text = version.credential else { throw RefreshFailure.invalidCredential }
        var envelope = try ProviderCredentialEnvelope.decode(text, expectedProvider: .nousPortal)
        try NousPortalCredential.validateLocal(envelope, accountID: accountID, deviceID: vault.deviceID)
        let expires = envelope.expiresAt!
        let ttl = Double(envelope.metadata["issuedTTL"] ?? "") ?? 0
        let needsRefresh = expires.timeIntervalSince(now()) <= min(120, max(ttl / 4, 1))
        let state = envelope.metadata["rotationState"] ?? "active"
        if state != "active" {
            // A prior POST's result is unknown. Never resend its single-use refresh, including after restart.
            guard state != "terminal", expires > now() else { throw RefreshFailure.invalidCredential }
        } else if needsRefresh {
            let original = envelope
            envelope.metadata["rotationState"] = "pending"
            guard let pending = try await vault.compareAndSwap(expectedGeneration: version.generation, credential: envelope.encoded(), for: accountID) else { throw CancellationError() }
            version = pending
            do {
                let refreshed = try await NousPortalAuthenticator(transport: transport, now: now, deviceID: vault.deviceID)
                    .refresh(original, accountID: accountID)
                guard let saved = try await vault.compareAndSwap(expectedGeneration: version.generation, credential: refreshed.encoded(), for: accountID) else { throw CancellationError() }
                version = saved
                envelope = refreshed
            } catch {
                var retained = original
                let failure: RefreshFailure
                switch error {
                case NousRefreshError.safeRejection(let rejected): retained.metadata["rotationState"] = "active"; failure = rejected
                case NousRefreshError.terminal: retained.metadata["rotationState"] = "terminal"; retained.refreshToken = nil; failure = .invalidCredential
                default: retained.metadata["rotationState"] = "uncertain"; failure = ProviderHTTP.refreshFailure(error) as? RefreshFailure ?? .network
                }
                guard try await vault.compareAndSwap(expectedGeneration: version.generation, credential: retained.encoded(), for: accountID) != nil else { throw CancellationError() }
                throw failure
            }
        }
        do {
            let result = try await NousPortalProviderClient(transport: transport, now: now, deviceID: vault.deviceID).quota(accountID: accountID, credential: envelope)
            let latest = try await vault.version(for: accountID)
            guard latest.generation == version.generation else { throw CancellationError() }
            return result.snapshot
        } catch {
            let latest = try await vault.version(for: accountID)
            guard latest.generation == version.generation else { throw CancellationError() }
            if error as? RefreshFailure == .invalidCredential {
                var retained = envelope
                retained.metadata["rotationState"] = "terminal"
                retained.refreshToken = nil
                guard try await vault.compareAndSwap(expectedGeneration: version.generation, credential: retained.encoded(), for: accountID) != nil else { throw CancellationError() }
            }
            throw error
        }
    }
}
