import Foundation
import XCTest
@testable import TokenPulse

actor WalletExpansionTransport: ProviderTransport {
    private var status: Int
    private let body: String
    private let secondBody: String?
    private var received: [URLRequest] = []
    init(status: Int = 200, body: String, secondBody: String? = nil) {
        self.status = status
        self.body = body
        self.secondBody = secondBody
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        received.append(request)
        let selected = request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-b" ? secondBody ?? body : body
        return (Data(selected.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { received }
    func fail() { status = 401 }
}

actor WalletExpansionCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) async throws { values[accountID] = credential }
    func credential(for accountID: UUID) async throws -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) async throws { values[accountID] = nil }
}

extension XCTestCase {
    func assertWalletExpansionRequest(provider: Provider, body: String, endpoint: URL,
                                      file: StaticString = #filePath, line: UInt = #line) async throws {
        let transport = WalletExpansionTransport(body: body)
        let key = try ProviderAuthenticationController().credential(provider: provider, apiKey: " fixture-a ")
        let id = UUID()
        let client = ProviderQuotaClient(provider: provider, transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let result = try await client.quotaResult(for: id, credential: key)
        XCTAssertEqual(result.snapshot.accountID, id, file: file, line: line)
        XCTAssertEqual(result.snapshot.collectedAt, Date(timeIntervalSince1970: 100), file: file, line: line)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first, file: file, line: line)
        XCTAssertEqual(request.url, endpoint, file: file, line: line)
        XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-a", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)
        XCTAssertFalse(request.url?.absoluteString.contains("fixture-a") == true, file: file, line: line)
        XCTAssertNil(result.updatedCredential, file: file, line: line)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (503, .server)] {
            let failing = ProviderQuotaClient(provider: provider, transport: WalletExpansionTransport(status: status, body: "{}"))
            do { _ = try await failing.quota(for: id, credential: key); XCTFail("Expected failure", file: file, line: line) }
            catch { XCTAssertEqual(error as? RefreshFailure, expected, file: file, line: line) }
        }
    }

    @MainActor
    func assertWalletExpansionLifecycle(provider: Provider, body: String, secondBody: String,
                                        file: StaticString = #filePath, line: UInt = #line) async throws {
        let suite = "com.tokenpulse.tests.wallet-expansion-lifecycle.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "cloudSyncEnabled")
        let keys = WalletExpansionCredentials()
        let transport = WalletExpansionTransport(body: body, secondBody: secondBody)
        let client = ProviderQuotaClient(provider: provider, transport: transport)
        func monitor() -> QuotaMonitor {
            QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: keys,
                         quotaClient: client, configurationStore: LocalAccountConfigurationStore(suiteName: suite),
                         providerClient: { _ in client })
        }
        let original = monitor()
        await original.start(refresh: false)
        let controller = ProviderAuthenticationController()
        let keyA = try controller.credential(provider: provider, apiKey: "fixture-a")
        let keyB = try controller.credential(provider: provider, apiKey: "fixture-b")
        await original.addAccount(name: "A", credential: keyA, provider: provider)
        await original.addAccount(name: "B", credential: keyB, provider: provider)
        let a = try XCTUnwrap(original.states.first { $0.account.name == "A" })
        let b = try XCTUnwrap(original.states.first { $0.account.name == "B" })
        XCTAssertNotNil(a.snapshot, file: file, line: line)
        XCTAssertNotEqual(a.snapshot?.windows.first?.wallet?.total, b.snapshot?.windows.first?.wallet?.total, file: file, line: line)
        await transport.fail()
        await original.refresh(accountID: a.id)
        XCTAssertEqual(original.states.first { $0.id == a.id }?.snapshot, a.snapshot, file: file, line: line)
        XCTAssertEqual(original.states.first { $0.id == a.id }?.lastFailure, .invalidCredential, file: file, line: line)
        XCTAssertNil(original.states.first { $0.id == b.id }?.lastFailure, file: file, line: line)
        let reopened = monitor()
        await reopened.start(refresh: false)
        XCTAssertEqual(reopened.states, original.states, file: file, line: line)
        let storedA = try await keys.credential(for: a.id)
        let storedB = try await keys.credential(for: b.id)
        XCTAssertEqual(storedA, keyA, file: file, line: line)
        XCTAssertEqual(storedB, keyB, file: file, line: line)
        let widgetStore = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "test.widgets")
        try await widgetStore.save(states: reopened.states, configurations: reopened.configurations)
        let widgets = await widgetStore.load()
        XCTAssertEqual(widgets.first { $0.id == a.id }?.collectedAt, a.snapshot?.collectedAt, file: file, line: line)
        XCTAssertEqual(widgets.first { $0.id == a.id }?.lastFailure, .invalidCredential, file: file, line: line)
        let synced = try JSONDecoder().decode([AccountQuotaState].self, from: JSONEncoder().encode(reopened.states))
        XCTAssertEqual(synced, reopened.states, file: file, line: line)
        let deleted = await reopened.deleteAccount(accountID: a.id)
        XCTAssertTrue(deleted, file: file, line: line)
        let deletedKey = try await keys.credential(for: a.id)
        XCTAssertNil(deletedKey, file: file, line: line)
        XCTAssertEqual(reopened.states.map(\.id), [b.id], file: file, line: line)
    }
}
