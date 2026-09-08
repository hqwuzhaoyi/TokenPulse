import Foundation
import Security

struct KeychainCredentialStore: CredentialStoring {
    private let service: String

    init(service: String = "com.tokenpulse.minimax-credentials") {
        self.service = service
    }

    func save(_ credential: String, for accountID: UUID) async throws {
        let data = Data(credential.utf8)
        let lookup = query(for: accountID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var insertion = lookup
        attributes.forEach { insertion[$0.key] = $0.value }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func credential(for accountID: UUID) async throws -> String? {
        var lookup = query(for: accountID)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let credential = String(data: data, encoding: .utf8)
        else { throw KeychainError(status: status) }
        return credential
    }

    func deleteCredential(for accountID: UUID) async throws {
        let status = SecItemDelete(query(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func query(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }
}
struct KeychainError: Error, Equatable {
    let status: OSStatus
}
