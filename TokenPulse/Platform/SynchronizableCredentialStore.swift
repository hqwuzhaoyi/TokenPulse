import Foundation
import Security

struct CredentialSyncIssue: Error, Equatable, Sendable {
    let accountID: UUID
    let status: OSStatus
}

actor SynchronizableCredentialStore: CredentialStoring {
    private struct Item {
        let credential: String
        let modifiedAt: Date
        let synchronizable: Bool
    }

    private let service: String
    private let accessGroup: String?
    private var syncEnabled: Bool
    private(set) var credentialSyncIssue: CredentialSyncIssue?

    init(
        service: String = PlatformConstants.credentialService,
        accessGroup: String? = PlatformConstants.resolvedKeychainAccessGroup,
        syncEnabled: Bool = true
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.syncEnabled = syncEnabled
    }

    func setSyncEnabled(_ enabled: Bool) {
        syncEnabled = enabled
        credentialSyncIssue = nil
    }

    func save(_ credential: String, for accountID: UUID) throws {
        try upsert(credential, for: accountID, synchronizable: false)
        guard syncEnabled else { return }
        do {
            try upsert(credential, for: accountID, synchronizable: true)
            credentialSyncIssue = nil
        } catch let error as KeychainError {
            credentialSyncIssue = CredentialSyncIssue(accountID: accountID, status: error.status)
        }
    }

    func credential(for accountID: UUID) throws -> String? {
        guard syncEnabled else { return try read(for: accountID, synchronizable: false)?.credential }
        var items: [Item] = []
        var readFailure: KeychainError?
        for synchronizable in [false, true] {
            do {
                if let item = try read(for: accountID, synchronizable: synchronizable) {
                    items.append(item)
                }
            } catch let error as KeychainError {
                readFailure = readFailure ?? error
            }
        }
        guard let newest = items.max(by: Self.isOlder) else {
            if let readFailure { throw readFailure }
            return nil
        }

        do {
            if items.first(where: { $0.synchronizable })?.credential != newest.credential {
                try upsert(newest.credential, for: accountID, synchronizable: true)
            }
            if items.first(where: { !$0.synchronizable })?.credential != newest.credential {
                try upsert(newest.credential, for: accountID, synchronizable: false)
            }
            credentialSyncIssue = nil
        } catch let error as KeychainError {
            credentialSyncIssue = CredentialSyncIssue(accountID: accountID, status: error.status)
        }
        return newest.credential
    }

    func deleteCredential(for accountID: UUID) throws {
        var firstFailure: KeychainError?
        for synchronizable in syncEnabled ? [true, false] : [false] {
            let status = SecItemDelete(query(for: accountID, synchronizable: synchronizable) as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound, firstFailure == nil {
                firstFailure = KeychainError(status: status)
            }
        }
        if let firstFailure { throw firstFailure }
        credentialSyncIssue = nil
    }

    nonisolated private static func isOlder(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        return !lhs.synchronizable && rhs.synchronizable
    }

    private func upsert(_ credential: String, for accountID: UUID, synchronizable: Bool) throws {
        let lookup = query(for: accountID, synchronizable: synchronizable)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(credential.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var insertion = lookup
        attributes.forEach { insertion[$0.key] = $0.value }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    private func read(for accountID: UUID, synchronizable: Bool) throws -> Item? {
        var lookup = query(for: accountID, synchronizable: synchronizable)
        lookup[kSecReturnAttributes as String] = true
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data,
              let credential = String(data: data, encoding: .utf8),
              let modifiedAt = attributes[kSecAttrModificationDate as String] as? Date
        else { throw KeychainError(status: status == errSecSuccess ? errSecDecode : status) }
        return Item(credential: credential, modifiedAt: modifiedAt, synchronizable: synchronizable)
    }

    private func query(for accountID: UUID, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrSynchronizable as String: synchronizable,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
