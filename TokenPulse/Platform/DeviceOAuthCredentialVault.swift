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
    init(records: any DeviceOAuthRecordStoring = KeychainDeviceOAuthRecords(), deviceID: String = DeviceOAuthIdentity.id) {
        self.records = records
        self.deviceID = deviceID
    }
    func version(for accountID: UUID) throws -> DeviceCredentialVersion {
        guard let data = try records.read(accountID) else { return .init(credential: nil, generation: 0) }
        return try JSONDecoder().decode(DeviceCredentialVersion.self, from: data)
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
        if provider == .nousPortal {
            let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
            try NousPortalCredential.validateLocal(envelope, accountID: accountID, deviceID: deviceOAuthVault.deviceID)
            try await deviceOAuthVault.save(credential, for: accountID)
        } else {
            // Call-site context cannot override the actual secret's distribution policy.
            guard !Self.isDeviceOnlyEnvelope(credential) else { throw ProviderIntegrationError.invalidCredentialData }
            try await synchronized.save(credential, for: accountID)
        }
    }
    func credential(for accountID: UUID, provider: Provider) async throws -> String? {
        if provider == .nousPortal { return try await deviceOAuthVault.version(for: accountID).credential }
        return try await synchronized.credential(for: accountID)
    }
    func deleteCredential(for accountID: UUID, provider: Provider) async throws {
        if provider == .nousPortal { try await deviceOAuthVault.delete(for: accountID) }
        else { try await synchronized.deleteCredential(for: accountID) }
    }
    // Unscoped methods are retained only for API compatibility; product call sites pass provider explicitly.
    func save(_ credential: String, for accountID: UUID) async throws {
        if Self.isDeviceOnlyEnvelope(credential) {
            try await save(credential, for: accountID, provider: .nousPortal)
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
        return object["provider"] as? String == Provider.nousPortal.rawValue
    }
}
