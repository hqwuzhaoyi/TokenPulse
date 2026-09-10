import Combine
import Foundation

@MainActor
final class QuotaMonitor: ObservableObject {
    @Published private(set) var states: [AccountQuotaState] = []
    @Published private(set) var refreshingAccountIDs: Set<UUID> = []
    @Published private(set) var storageMessage: String?
    @Published private(set) var synchronizedConfigurations: [AccountConfiguration] = []
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

    var configurations: [AccountConfiguration] {
        synchronizedConfigurations.filter { $0.deletedAt == nil }
    }

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
            synchronizedConfigurations = try await configurationStore?.load() ?? []
            for state in states where !synchronizedConfigurations.contains(where: { $0.id == state.id }) {
                synchronizedConfigurations.append(AccountConfiguration(account: state.account))
            }
            let deletedIDs = Set(synchronizedConfigurations.filter { $0.deletedAt != nil }.map(\.id))
            let storedCount = states.count
            states.removeAll { deletedIDs.contains($0.id) }
            if states.count != storedCount {
                do { try await accountStore.save(states) }
                catch { storageMessage = "账号已删除，本地额度缓存清理失败。" }
            }
            for configuration in configurations where !states.contains(where: { $0.id == configuration.id }) {
                states.append(AccountQuotaState(account: configuration.account))
            }
            for accountID in deletedIDs { await cleanupCredential(for: accountID) }
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
        synchronizedConfigurations.append(AccountConfiguration(account: account))
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
            guard let index = states.firstIndex(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
            guard !Task.isCancelled else { return }
            guard snapshot.accountID == accountID else { throw RefreshFailure.unreadableResponse }
            states[index].snapshot = snapshot
            states[index].lastFailure = nil
            await onFreshSnapshot?(states[index], previous)
        } catch is CancellationError {
            if !states.contains(where: { $0.id == accountID }) { await cleanupCredential(for: accountID) }
            return
        } catch let failure as RefreshFailure {
            guard let index = states.firstIndex(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
            states[index].lastFailure = failure
        } catch {
            guard let index = states.firstIndex(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
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
        guard let index = synchronizedConfigurations.firstIndex(where: { $0.id == accountID && $0.deletedAt == nil }) else { return }
        synchronizedConfigurations[index].reminders = settings
        synchronizedConfigurations[index].modifiedAt = Date()
        await persistConfigurations()
    }

    func reorderAccounts(from offsets: IndexSet, to destination: Int) {
        var reordered = states
        let moved = offsets.sorted().map { reordered[$0] }
        for index in offsets.sorted().reversed() { reordered.remove(at: index) }
        let insertionIndex = destination - offsets.filter { $0 < destination }.count
        reordered.insert(contentsOf: moved, at: insertionIndex)
        states = reordered

        let positionByID = Dictionary(uniqueKeysWithValues: states.enumerated().map { ($1.id, $0) })
        synchronizedConfigurations.sort {
            (positionByID[$0.id] ?? .max) < (positionByID[$1.id] ?? .max)
        }
        let modifiedAt = Date()
        for index in synchronizedConfigurations.indices where synchronizedConfigurations[index].deletedAt == nil {
            synchronizedConfigurations[index].modifiedAt = modifiedAt
        }
    }

    func persistAccountOrder() async {
        do {
            try await accountStore.save(states)
            try await configurationStore?.save(synchronizedConfigurations)
        } catch {
            storageMessage = "无法保存账号顺序"
        }
        await onChange?()
    }

    @discardableResult
    func deleteAccount(accountID: UUID) async -> Bool {
        guard states.contains(where: { $0.id == accountID }),
              let configurationIndex = synchronizedConfigurations.firstIndex(where: { $0.id == accountID }) else { return false }
        var deleted = synchronizedConfigurations[configurationIndex]
        deleted.deletedAt = Date()
        var savedConfigurations = synchronizedConfigurations
        savedConfigurations[configurationIndex] = deleted
        do {
            // Persist the deletion before removing snapshots or credentials so stale sync cannot restore it.
            if let configurationStore {
                try await configurationStore.save(savedConfigurations)
            } else {
                try await accountStore.save(states.filter { $0.id != accountID })
            }
        } catch {
            storageMessage = "无法删除账号，请重试。"
            return false
        }
        if let index = synchronizedConfigurations.firstIndex(where: { $0.id == accountID }) {
            synchronizedConfigurations[index] = deleted
        }
        states.removeAll { $0.id == accountID }
        if configurationStore != nil {
            do { try await accountStore.save(states) }
            catch { storageMessage = "账号已删除，本地额度缓存清理失败。" }
        }
        await cleanupCredential(for: accountID)
        await onChange?()
        return true
    }

    private func cleanupCredential(for accountID: UUID) async {
        do {
            try await credentialStore.deleteCredential(for: accountID)
            pendingCredentialCleanupAccountIDs.remove(accountID)
        } catch {
            pendingCredentialCleanupAccountIDs.insert(accountID)
            storageMessage = "账号已删除，凭证清理失败，请重试。"
        }
    }

    func replaceCredential(_ credential: String, accountID: UUID) async {
        guard states.contains(where: { $0.id == accountID }), !credential.isEmpty else { return }
        do {
            try await credentialStore.save(credential, for: accountID)
            guard states.contains(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
            await refresh(accountID: accountID)
        } catch { storageMessage = "无法安全保存凭证" }
    }

    func mergeSynchronized(configurations incoming: [AccountConfiguration], states incomingStates: [AccountQuotaState]) async {
        for configuration in incoming {
            if let index = synchronizedConfigurations.firstIndex(where: { $0.id == configuration.id }) {
                if configuration.deletedAt != nil || (synchronizedConfigurations[index].deletedAt == nil
                    && configuration.modifiedAt > synchronizedConfigurations[index].modifiedAt) {
                    synchronizedConfigurations[index] = configuration
                }
            } else { synchronizedConfigurations.append(configuration) }
        }
        let deletedIDs = Set(synchronizedConfigurations.filter { $0.deletedAt != nil }.map(\.id))
        states.removeAll { deletedIDs.contains($0.id) }
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
            try await configurationStore?.save(synchronizedConfigurations)
            try await accountStore.save(states)
        } catch { storageMessage = "无法保存同步数据" }
        for accountID in deletedIDs { await cleanupCredential(for: accountID) }
    }

    func setSynchronizationMessage(_ message: String?) { synchronizationMessage = message }

    private func persistConfigurations() async {
        do { try await configurationStore?.save(synchronizedConfigurations) }
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
