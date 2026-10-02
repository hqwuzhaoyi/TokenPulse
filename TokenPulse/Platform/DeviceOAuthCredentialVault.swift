import Foundation
import Security

/// Public, device-local identifier. Tokens are never placed in defaults or shared across devices.
enum DeviceOAuthIdentity {
    static let id: String = {
        let key = "tokenpulse.deviceOAuth.installationID"
        if let value = UserDefaults.standard.string(forKey: key), UUID(uuidString: value) != nil { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
}

protocol DeviceOAuthRecordStoring: Sendable {
    func read(_ accountID: UUID) throws -> Data?
    func write(_ data: Data, for accountID: UUID) throws
}

struct KeychainDeviceOAuthRecords: DeviceOAuthRecordStoring {
    let service: String
    init(service: String = PlatformConstants.credentialService + ".device-oauth") { self.service = service }
    func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString, kSecAttrSynchronizable as String: false]
    }
    func read(_ accountID: UUID) throws -> Data? {
        var query = query(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }
    func write(_ data: Data, for accountID: UUID) throws {
        let lookup = query(accountID)
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(lookup as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var item = lookup
        values.forEach { item[$0.key] = $0.value }
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }
}

struct DeviceCredentialVersion: Codable, Equatable, Sendable {
    let credential: String?
    let generation: UInt64
}

/// All synchronous read/CAS/write work is within this actor, including tombstones after deletion.
actor DeviceOAuthCredentialVault {
    static let shared = DeviceOAuthCredentialVault()
    nonisolated let deviceID: String
    private let records: any DeviceOAuthRecordStoring
    private let now: @Sendable () -> Date
    private static let grantLedgerID = UUID(uuidString: "A68A0000-0000-0000-0000-000000000001")!
    init(records: any DeviceOAuthRecordStoring = KeychainDeviceOAuthRecords(), deviceID: String = DeviceOAuthIdentity.id,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.records = records
        self.deviceID = deviceID
        self.now = now
    }
    func version(for accountID: UUID) throws -> DeviceCredentialVersion {
        guard accountID != Self.grantLedgerID else { throw ProviderIntegrationError.invalidCredentialData }
        guard let data = try records.read(accountID) else { return .init(credential: nil, generation: 0) }
        return try JSONDecoder().decode(DeviceCredentialVersion.self, from: data)
    }
    /// Only high-entropy refresh-token digests are retained, including after account deletion.
    /// This prevents local replay under another UUID; it is not a global cross-device family lock.
    func reserveGrantMarker(_ marker: String, accountID: UUID) throws -> Bool {
        guard accountID != Self.grantLedgerID,
              marker.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil else { throw RefreshFailure.invalidCredential }
        var ledger: [String: UUID] = [:]
        if let data = try records.read(Self.grantLedgerID) { ledger = try JSONDecoder().decode([String: UUID].self, from: data) }
        if let owner = ledger[marker] {
            guard owner == accountID else { throw RefreshFailure.invalidCredential }
            return false
        }
        guard ledger.count < 4_096 else { throw RefreshFailure.invalidCredential }
        ledger[marker] = accountID
        try records.write(JSONEncoder().encode(ledger), for: Self.grantLedgerID)
        return true
    }
    /// JetBrains prepare receipts are activated only by the user's actual save/replace operation.
    /// All checks and both record writes happen in this actor without an intervening await.
    func activateJetBrainsReceipt(_ receipt: ProviderCredentialEnvelope, accountID: UUID) throws {
        try JetBrainsCredential.validateLocal(receipt, accountID: accountID, deviceID: deviceID)
        let current = try version(for: accountID)
        if let text = current.credential {
            let active = try ProviderCredentialEnvelope.decode(text, expectedProvider: .jetBrainsAI)
            try JetBrainsCredential.validateLocal(active, accountID: accountID, deviceID: deviceID)
            if active.metadata["grantMarker"] == receipt.metadata["grantMarker"],
               try JetBrainsCredential.fingerprint(active) == JetBrainsCredential.fingerprint(receipt) {
                // Acknowledge the current version; never overwrite a later rotation with stale UI bytes.
                return
            }
        }
        guard let candidateText = receipt.metadata["candidateRecordID"], let candidateID = UUID(uuidString: candidateText),
              candidateID != accountID, let generationText = receipt.metadata["candidateGeneration"], let generation = UInt64(generationText),
              let baselineText = receipt.metadata["activeBaselineGeneration"], let baseline = UInt64(baselineText),
              baseline == current.generation, let deadlineText = receipt.metadata["candidateDeadline"], let deadline = Double(deadlineText),
              deadline.isFinite, deadline > now().timeIntervalSince1970 else { throw RefreshFailure.invalidCredential }
        let candidate = try version(for: candidateID)
        guard let data = candidate.credential else { throw RefreshFailure.invalidCredential }
        var prepared = try ProviderCredentialEnvelope.decode(data, expectedProvider: .jetBrainsAI)
        try JetBrainsCredential.validateLocal(prepared, accountID: accountID, deviceID: deviceID)
        guard prepared.metadata["candidateRecordID"] == candidateText, prepared.metadata["candidateGeneration"] == generationText,
              prepared.metadata["activeBaselineGeneration"] == baselineText, prepared.metadata["grantMarker"] == receipt.metadata["grantMarker"],
              try JetBrainsCredential.fingerprint(prepared) == JetBrainsCredential.fingerprint(receipt),
              (prepared.metadata["stage"] == "ready" && candidate.generation == generation)
                || (prepared.metadata["stage"] == "activationPending" && generation < UInt64.max && candidate.generation == generation + 1) else {
            throw RefreshFailure.invalidCredential
        }
        var claimedGeneration = candidate.generation
        if prepared.metadata["stage"] == "ready" {
            prepared.metadata["stage"] = "activationPending"
            claimedGeneration = try write(prepared.encoded(), generation: candidate.generation, for: candidateID).generation
        }
        prepared.metadata["stage"] = "ready"
        for key in ["candidateRecordID", "candidateGeneration", "activeBaselineGeneration", "candidateDeadline"] { prepared.metadata.removeValue(forKey: key) }
        _ = try write(prepared.encoded(), generation: current.generation, for: accountID)
        // If clearing the candidate fails, activationPending still forbids any native refresh on that duplicate.
        _ = try? write(nil, generation: claimedGeneration, for: candidateID)
    }
    func save(_ credential: String, for accountID: UUID) throws {
        let current = try version(for: accountID)
        _ = try write(credential, generation: current.generation, for: accountID)
    }
    func delete(for accountID: UUID) throws {
        let current = try version(for: accountID)
        _ = try write(nil, generation: current.generation, for: accountID)
    }
    func compareAndSwap(expectedGeneration: UInt64, credential: String?, for accountID: UUID) throws -> DeviceCredentialVersion? {
        let current = try version(for: accountID)
        guard current.generation == expectedGeneration else { return nil }
        return try write(credential, generation: expectedGeneration, for: accountID)
    }
    private func write(_ credential: String?, generation: UInt64, for accountID: UUID) throws -> DeviceCredentialVersion {
        guard generation < UInt64.max else { throw ProviderIntegrationError.invalidCredentialData }
        let updated = DeviceCredentialVersion(credential: credential, generation: generation + 1)
        try records.write(JSONEncoder().encode(updated), for: accountID)
        return updated
    }
}

protocol DeviceOAuthVaultProviding: Sendable {
    var deviceOAuthVault: DeviceOAuthCredentialVault { get }
}

struct ProviderScopedCredentialStore: CredentialStoring, DeviceOAuthVaultProviding {
    let synchronized: any CredentialStoring
    let deviceOAuthVault: DeviceOAuthCredentialVault
    init(synchronized: any CredentialStoring, deviceOAuthVault: DeviceOAuthCredentialVault = .shared) {
        self.synchronized = synchronized
        self.deviceOAuthVault = deviceOAuthVault
    }
    func save(_ credential: String, for accountID: UUID, provider: Provider) async throws {
        if provider.requiresDeviceLocalCredential {
            let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
            if provider == .jetBrainsAI {
                try await deviceOAuthVault.activateJetBrainsReceipt(envelope, accountID: accountID)
            } else {
                try NousPortalCredential.validateLocal(envelope, accountID: accountID, deviceID: deviceOAuthVault.deviceID)
                try await deviceOAuthVault.save(credential, for: accountID)
            }
        } else {
            // Call-site context cannot override the actual secret's distribution policy.
            guard !Self.isDeviceOnlyEnvelope(credential) else { throw ProviderIntegrationError.invalidCredentialData }
            try await synchronized.save(credential, for: accountID)
        }
    }
    func credential(for accountID: UUID, provider: Provider) async throws -> String? {
        if provider.requiresDeviceLocalCredential { return try await deviceOAuthVault.version(for: accountID).credential }
        return try await synchronized.credential(for: accountID)
    }
    func deleteCredential(for accountID: UUID, provider: Provider) async throws {
        if provider.requiresDeviceLocalCredential { try await deviceOAuthVault.delete(for: accountID) }
        else { try await synchronized.deleteCredential(for: accountID) }
    }
    // Unscoped methods are retained only for API compatibility; product call sites pass provider explicitly.
    func save(_ credential: String, for accountID: UUID) async throws {
        if Self.isDeviceOnlyEnvelope(credential) {
            struct Header: Decodable { let provider: Provider }
            let provider = try JSONDecoder().decode(Header.self, from: Data(credential.utf8)).provider
            try await save(credential, for: accountID, provider: provider)
        } else { try await synchronized.save(credential, for: accountID) }
    }
    func credential(for accountID: UUID) async throws -> String? {
        // An unqualified read must not trigger synchronizable-store backfill for an unknown provider.
        throw ProviderIntegrationError.invalidCredentialData
    }
    func deleteCredential(for accountID: UUID) async throws {
        try await deviceOAuthVault.delete(for: accountID)
        try await synchronized.deleteCredential(for: accountID)
    }
    private static func isDeviceOnlyEnvelope(_ credential: String) -> Bool {
        guard let data = credential.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["provider"] as? String).flatMap(Provider.init(rawValue:))?.requiresDeviceLocalCredential == true
    }
}
