import Combine
import Foundation

@MainActor
final class QuotaMonitor: ObservableObject {
    @Published private(set) var states: [AccountQuotaState] = []
    @Published private(set) var refreshingAccountIDs: Set<UUID> = []
    @Published private(set) var storageMessage: String?
    @Published private(set) var configurations: [AccountConfiguration] = []
    @Published private(set) var synchronizationMessage: String?
    @Published private var pendingCredentialCleanupAccountIDs: Set<UUID> = []

    private let accountStore: AccountStateStoring
    private let credentialStore: CredentialStoring
    private let quotaClient: QuotaQuerying
    private let configurationStore: (any AccountConfigurationStoring)?
    private let providerClient: (@Sendable (Provider) -> any QuotaQuerying)?
    private var started = false

    var onChange: (@MainActor () async -> Void)?
    var onFreshSnapshot: (@MainActor (AccountQuotaState, AccountQuotaState?) async -> Void)?

    var hasPendingCredentialCleanup: Bool {
        !pendingCredentialCleanupAccountIDs.isEmpty
    }

    init(accountStore: AccountStateStoring,
         credentialStore: CredentialStoring,
         quotaClient: QuotaQuerying,
         configurationStore: (any AccountConfigurationStoring)? = nil,
         providerClient: (@Sendable (Provider) -> any QuotaQuerying)? = nil) {
        self.accountStore = accountStore
        self.credentialStore = credentialStore
        self.quotaClient = quotaClient
        self.configurationStore = configurationStore
        self.providerClient = providerClient
    }

    func start(refresh: Bool = true) async {
        guard !started else { return }
        started = true
        do {
            states = try await accountStore.load()
            configurations = try await configurationStore?.load() ?? []
            for state in states where !configurations.contains(where: { $0.id == state.id }) {
                configurations.append(AccountConfiguration(account: state.account))
            }
            for configuration in configurations where !states.contains(where: { $0.id == configuration.id }) {
                states.append(AccountQuotaState(account: configuration.account))
            }
            if refresh { await refreshAll() }
        } catch is CancellationError {
            return
        } catch {
            storageMessage = "无法读取本地账号"
        }
    }

    func applicationDidBecomeActive() async {
        guard started else { return }
        await refreshAll()
    }

    func addAccount(name: String, credential: String, provider: Provider = .miniMaxChina) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCredential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCredential.isEmpty else { return }

        let account = SubscriptionAccount(name: trimmedName, provider: provider)
        do {
            try await credentialStore.save(trimmedCredential, for: account.id)
            states.append(AccountQuotaState(account: account, snapshot: nil, lastFailure: nil))
            do {
                try await accountStore.save(states)
            } catch {
                states.removeAll { $0.id == account.id }
                do {
                    try await credentialStore.deleteCredential(for: account.id)
                    storageMessage = "无法安全保存账号"
                } catch {
                    pendingCredentialCleanupAccountIDs.insert(account.id)
                    storageMessage = "账号未保存，凭证清理失败，请重试。"
                }
                return
            }
        } catch {
            storageMessage = "无法安全保存账号"
            return
        }
        configurations.append(AccountConfiguration(account: account))
        await persistConfigurations()
        await refresh(accountID: account.id)
    }

    func refreshAll() async {
        for state in states {
            guard !Task.isCancelled else { return }
            await refresh(accountID: state.id)
        }
    }

    func refresh(accountID: UUID) async {
        guard let previous = states.first(where: { $0.id == accountID }),
              !refreshingAccountIDs.contains(accountID) else { return }

        refreshingAccountIDs.insert(accountID)
        defer { refreshingAccountIDs.remove(accountID) }

        do {
            guard let credential = try await credentialStore.credential(for: accountID),
                  !credential.isEmpty else {
                throw RefreshFailure.invalidCredential
            }
            let client = providerClient?(previous.account.provider) ?? quotaClient
            let snapshot = try await client.quota(for: accountID, credential: credential)
            guard !Task.isCancelled, let index = states.firstIndex(where: { $0.id == accountID }) else { return }
            guard snapshot.accountID == accountID else { throw RefreshFailure.unreadableResponse }
            states[index].snapshot = snapshot
            states[index].lastFailure = nil
            await onFreshSnapshot?(states[index], previous)
        } catch is CancellationError {
            return
        } catch let failure as RefreshFailure {
            guard let index = states.firstIndex(where: { $0.id == accountID }) else { return }
            states[index].lastFailure = failure
        } catch {
            guard let index = states.firstIndex(where: { $0.id == accountID }) else { return }
            states[index].lastFailure = .server
        }

        do {
            try await accountStore.save(states)
        } catch {
            storageMessage = "无法保存刷新结果"
        }
        await onChange?()
    }

    func configuration(for id: UUID) -> AccountConfiguration? {
        configurations.first { $0.id == id }
    }

    func updateReminders(_ settings: AccountReminderSettings, accountID: UUID) async {
        guard let index = configurations.firstIndex(where: { $0.id == accountID }) else { return }
        configurations[index].reminders = settings
        configurations[index].modifiedAt = Date()
        await persistConfigurations()
    }

    func reorderAccounts(from offsets: IndexSet, to destination: Int) {
        let moved = offsets.sorted().map { states[$0] }
        for index in offsets.sorted().reversed() { states.remove(at: index) }
        let insertionIndex = destination - offsets.filter { $0 < destination }.count
        states.insert(contentsOf: moved, at: insertionIndex)

        let positionByID = Dictionary(uniqueKeysWithValues: states.enumerated().map { ($1.id, $0) })
        configurations.sort {
            (positionByID[$0.id] ?? .max) < (positionByID[$1.id] ?? .max)
        }
        let modifiedAt = Date()
        for index in configurations.indices { configurations[index].modifiedAt = modifiedAt }
    }

    func persistAccountOrder() async {
        do {
            try await accountStore.save(states)
            try await configurationStore?.save(configurations)
        } catch {
            storageMessage = "无法保存账号顺序"
        }
        await onChange?()
    }

    func replaceCredential(_ credential: String, accountID: UUID) async {
        guard states.contains(where: { $0.id == accountID }), !credential.isEmpty else { return }
        do {
            try await credentialStore.save(credential, for: accountID)
            await refresh(accountID: accountID)
        } catch { storageMessage = "无法安全保存凭证" }
    }

    func mergeSynchronized(configurations incoming: [AccountConfiguration], states incomingStates: [AccountQuotaState]) async {
        for configuration in incoming {
            if let index = configurations.firstIndex(where: { $0.id == configuration.id }) {
                if configuration.modifiedAt > configurations[index].modifiedAt { configurations[index] = configuration }
            } else { configurations.append(configuration) }
        }
        for configuration in configurations {
            if let index = states.firstIndex(where: { $0.id == configuration.id }) {
                states[index].account = configuration.account
            } else { states.append(AccountQuotaState(account: configuration.account)) }
        }
        for incomingState in incomingStates {
            guard let snapshot = incomingState.snapshot, snapshot.accountID == incomingState.id,
                  let index = states.firstIndex(where: { $0.id == incomingState.id }) else { continue }
            if snapshot.collectedAt > (states[index].snapshot?.collectedAt ?? .distantPast) {
                states[index].snapshot = snapshot
            }
        }
        do {
            try await accountStore.save(states)
            try await configurationStore?.save(configurations)
        } catch { storageMessage = "无法保存同步数据" }
    }

    func setSynchronizationMessage(_ message: String?) { synchronizationMessage = message }

    private func persistConfigurations() async {
        do { try await configurationStore?.save(configurations) }
        catch { storageMessage = "无法保存账号设置" }
        await onChange?()
    }

    func dismissStorageMessage() {
        storageMessage = nil
    }

    func retryPendingCredentialCleanup() async {
        for accountID in pendingCredentialCleanupAccountIDs {
            do {
                try await credentialStore.deleteCredential(for: accountID)
                pendingCredentialCleanupAccountIDs.remove(accountID)
            } catch {
                // Keep the identifier so the visible action can retry it.
            }
        }
        storageMessage = hasPendingCredentialCleanup
            ? "凭证清理仍失败，请重试。"
            : nil
    }
}
