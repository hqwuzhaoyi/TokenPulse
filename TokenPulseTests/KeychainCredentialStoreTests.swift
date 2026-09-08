import XCTest
@testable import TokenPulse

final class KeychainCredentialStoreTests: XCTestCase {
    func testCredentialRoundTripsByAccountAndCanBeDeleted() async throws {
        let store = KeychainCredentialStore(service: "com.tokenpulse.tests.\(UUID().uuidString)")
        let firstID = UUID()
        let secondID = UUID()
        defer {
            Task {
                try? await store.deleteCredential(for: firstID)
                try? await store.deleteCredential(for: secondID)
            }
        }

        try await store.save("first-secret", for: firstID)
        try await store.save("second-secret", for: secondID)

        let firstCredential = try await store.credential(for: firstID)
        let secondCredential = try await store.credential(for: secondID)
        XCTAssertEqual(firstCredential, "first-secret")
        XCTAssertEqual(secondCredential, "second-secret")
        try await store.deleteCredential(for: firstID)
        let deletedCredential = try await store.credential(for: firstID)
        let retainedCredential = try await store.credential(for: secondID)
        XCTAssertNil(deletedCredential)
        XCTAssertEqual(retainedCredential, "second-secret")
    }
}
