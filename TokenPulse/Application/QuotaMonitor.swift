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
    private var credentialRevisions: [UUID: Int] = [:]
    private var pendingCredentialRefreshes: Set<UUID> = []

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
            let statesBeforeBinding = states
            let configurationsBeforeBinding = synchronizedConfigurations
            for configuration in configurations where configuration.account.provider.requiresGatewayAddress || configuration.credentialIdentity != nil {
                if let credential = try await credentialStore.credential(for: configuration.id, provider: configuration.account.provider), credential != "demo" {
                    try? bindScopedCredential(credential, accountID: configuration.id, replacing: false)
                }
            }
            if states != statesBeforeBinding { try await accountStore.save(states) }
            if synchronizedConfigurations != configurationsBeforeBinding {
                try await configurationStore?.save(synchronizedConfigurations)
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

    func addAccount(name: String, credential: String, provider: Provider = .miniMaxChina, accountID: UUID = UUID()) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCredential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCredential.isEmpty,
              !states.contains(where: { $0.id == accountID }) else { return }

        if provider.requiresGatewayAddress, trimmedCredential != "demo",
           (try? ProviderCredentialEnvelope.decode(trimmedCredential, expectedProvider: provider).gatewayIdentity) == nil {
            storageMessage = "服务器地址与凭证无法绑定"
            return
        }
        let account = SubscriptionAccount(id: accountID, name: trimmedName, provider: provider)
        do {
            try await credentialStore.save(trimmedCredential, for: account.id, provider: provider)
            states.append(AccountQuotaState(account: account, snapshot: nil, lastFailure: nil))
            do {
                try await accountStore.save(states)
            } catch {
                states.removeAll { $0.id == account.id }
                do {
                    try await credentialStore.deleteCredential(for: account.id, provider: provider)
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
        if sourceIdentity(trimmedCredential, provider: provider) != nil {
            do { try bindScopedCredential(trimmedCredential, accountID: account.id, replacing: true) }
            catch { storageMessage = "服务器地址与凭证无法绑定" }
        }
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

        let revision = credentialRevisions[accountID, default: 0]
        refreshingAccountIDs.insert(accountID)
        defer {
            refreshingAccountIDs.remove(accountID)
            if pendingCredentialRefreshes.remove(accountID) != nil {
                Task { await self.refresh(accountID: accountID) }
            }
        }

        do {
            guard let credential = try await credentialStore.credential(for: accountID, provider: previous.account.provider),
                  !credential.isEmpty else {
                throw RefreshFailure.invalidCredential
            }
            if credential != "demo", previous.account.provider.requiresGatewayAddress || sourceIdentity(credential, provider: previous.account.provider) != nil || configuration(for: accountID)?.credentialIdentity != nil {
                try bindScopedCredential(credential, accountID: accountID, replacing: false)
            }
            let scopedPrevious = states.first { $0.id == accountID }
            let client = providerClient?(previous.account.provider) ?? quotaClient
            var snapshot = try await client.quota(for: accountID, credential: credential)
            guard let index = states.firstIndex(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
            guard !Task.isCancelled, credentialRevisions[accountID, default: 0] == revision else { return }
            if let identity = states[index].credentialIdentity {
                guard let latest = try await credentialStore.credential(for: accountID, provider: previous.account.provider),
                      sourceIdentity(latest, provider: previous.account.provider) == identity else { return }
                guard snapshot.sourceCredentialFingerprint == nil || snapshot.sourceCredentialFingerprint == identity else {
                    throw RefreshFailure.unreadableResponse
                }
                snapshot.sourceCredentialFingerprint = identity
            }
            guard credentialRevisions[accountID, default: 0] == revision,
                  let currentIndex = states.firstIndex(where: { $0.id == accountID }) else { return }
            guard snapshot.accountID == accountID else { throw RefreshFailure.unreadableResponse }
            snapshot = snapshot.retainingWalletAfterPartialFailure(from: scopedPrevious?.snapshot)
            states[currentIndex].snapshot = snapshot
            states[currentIndex].lastFailure = nil
            await onFreshSnapshot?(states[currentIndex], scopedPrevious)
        } catch is CancellationError {
            if !states.contains(where: { $0.id == accountID }) { await cleanupCredential(for: accountID) }
            return
        } catch let failure as RefreshFailure {
            guard credentialRevisions[accountID, default: 0] == revision else { return }
            guard let index = states.firstIndex(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
            states[index].lastFailure = failure
        } catch {
            guard credentialRevisions[accountID, default: 0] == revision else { return }
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

    func updateWatchFavorite(_ enabled: Bool, accountID: UUID) async {
        guard let index = synchronizedConfigurations.firstIndex(where: { $0.id == accountID && $0.deletedAt == nil }) else { return }
        synchronizedConfigurations[index].isWatchFavorite = enabled
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
            if let provider = synchronizedConfigurations.first(where: { $0.id == accountID })?.account.provider {
                try await credentialStore.deleteCredential(for: accountID, provider: provider)
            } else { try await credentialStore.deleteCredential(for: accountID) }
            pendingCredentialCleanupAccountIDs.remove(accountID)
        } catch {
            pendingCredentialCleanupAccountIDs.insert(accountID)
            storageMessage = "账号已删除，凭证清理失败，请重试。"
        }
    }

    func replaceCredential(_ credential: String, accountID: UUID, expectedIdentity: String? = nil) async {
        guard states.contains(where: { $0.id == accountID }), !credential.isEmpty else { return }
        do {
            if let expectedIdentity {
                guard configuration(for: accountID)?.credentialIdentity == expectedIdentity,
                      let provider = configuration(for: accountID)?.account.provider,
                      sourceIdentity(credential, provider: provider) == expectedIdentity else {
                    storageMessage = "请授权与此服务账号一致的 Nous 用户和组织。"
                    return
                }
            }
            if let provider = configuration(for: accountID)?.account.provider, provider.requiresGatewayAddress, credential != "demo",
               (try? ProviderCredentialEnvelope.decode(credential, expectedProvider: provider).gatewayIdentity) == nil {
                throw RefreshFailure.invalidCredential
            }
            if let configuration = configuration(for: accountID), configuration.credentialIdentity != nil,
               credential != "demo", sourceIdentity(credential, provider: configuration.account.provider) == nil {
                throw RefreshFailure.invalidCredential
            }
            guard let provider = configuration(for: accountID)?.account.provider else { return }
            try await credentialStore.save(credential, for: accountID, provider: provider)
            guard states.contains(where: { $0.id == accountID }) else {
                await cleanupCredential(for: accountID)
                return
            }
            if let expectedIdentity, configuration(for: accountID)?.credentialIdentity != expectedIdentity {
                if let local = credentialStore as? any DeviceOAuthVaultProviding {
                    let saved = try await local.deviceOAuthVault.version(for: accountID)
                    if saved.credential == credential {
                        _ = try await local.deviceOAuthVault.compareAndSwap(expectedGeneration: saved.generation, credential: nil, for: accountID)
                    }
                }
                return
            }
            credentialRevisions[accountID, default: 0] += 1
            if let provider = configuration(for: accountID)?.account.provider,
               sourceIdentity(credential, provider: provider) != nil {
                try bindScopedCredential(credential, accountID: accountID, replacing: true)
                try await accountStore.save(states)
                await persistConfigurations()
            }
            if refreshingAccountIDs.contains(accountID) { pendingCredentialRefreshes.insert(accountID) }
            else { await refresh(accountID: accountID) }
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
                if (configuration.credentialIdentity != nil || states[index].credentialIdentity != nil),
                   states[index].credentialIdentity != configuration.credentialIdentity {
                    credentialRevisions[configuration.id, default: 0] += 1
                    if let identity = configuration.credentialIdentity,
                       snapshotMatchesIdentity(states[index], identity: identity) {
                        states[index].snapshot?.sourceCredentialFingerprint = identity
                    } else {
                        states[index].snapshot = nil
                    }
                    states[index].lastFailure = nil
                    states[index].credentialIdentity = configuration.credentialIdentity
                }
            } else { states.append(AccountQuotaState(account: configuration.account)) }
        }
        for incomingState in incomingStates {
            guard let snapshot = incomingState.snapshot, snapshot.accountID == incomingState.id,
                  let index = states.firstIndex(where: { $0.id == incomingState.id }) else { continue }
            if incomingState.account.provider.requiresGatewayAddress || configuration(for: incomingState.id)?.credentialIdentity != nil {
                guard let identity = configuration(for: incomingState.id)?.credentialIdentity,
                      (incomingState.credentialIdentity ?? snapshot.sourceCredentialFingerprint) == identity,
                      snapshot.sourceCredentialFingerprint == nil || snapshot.sourceCredentialFingerprint == identity else { continue }
                states[index].credentialIdentity = identity
            }
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

    private func sourceIdentity(_ value: String, provider: Provider) -> String? {
        (try? identityEnvelope(value, provider: provider))?.sourceCredentialIdentity
    }

    /// MiniMax China keeps its existing raw-Key storage/query contract. This
    /// in-memory wrapper is only for scope calculation; it is never persisted.
    private func identityEnvelope(_ value: String, provider: Provider) throws -> ProviderCredentialEnvelope {
        if provider == .miniMaxChina {
            guard !value.isEmpty, value != "demo" else { throw RefreshFailure.invalidCredential }
            return ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: value)
        }
        return try ProviderCredentialEnvelope.decode(value, expectedProvider: provider)
    }

    private func bindScopedCredential(_ value: String, accountID: UUID, replacing: Bool) throws {
        guard let provider = configuration(for: accountID)?.account.provider else { throw RefreshFailure.invalidCredential }
        let envelope = try identityEnvelope(value, provider: provider)
        guard let identity = envelope.sourceCredentialIdentity,
              let stateIndex = states.firstIndex(where: { $0.id == accountID }),
              let configIndex = synchronizedConfigurations.firstIndex(where: { $0.id == accountID && $0.deletedAt == nil }) else {
            throw RefreshFailure.invalidCredential
        }
        // iCloud configuration and Keychain can arrive separately. Never query an
        // older Keychain item against a newly synchronized account binding.
        if !replacing, let expected = synchronizedConfigurations[configIndex].credentialIdentity, expected != identity {
            if !snapshotMatchesIdentity(states[stateIndex], identity: expected) {
                states[stateIndex].snapshot = nil
            }
            states[stateIndex].credentialIdentity = expected
            states[stateIndex].lastFailure = .invalidCredential
            throw RefreshFailure.invalidCredential
        }
        if states[stateIndex].credentialIdentity != identity {
            if !snapshotMatchesIdentity(states[stateIndex], identity: identity) {
                states[stateIndex].snapshot = nil
            }
            states[stateIndex].lastFailure = nil
        }
        states[stateIndex].credentialIdentity = identity
        if synchronizedConfigurations[configIndex].credentialIdentity != identity {
            synchronizedConfigurations[configIndex].credentialIdentity = identity
            synchronizedConfigurations[configIndex].serverAddress = envelope.gatewayAddress?.value
            if provider.requiresRegion, synchronizedConfigurations[configIndex].providerRegion != envelope.providerRegion {
                synchronizedConfigurations[configIndex].reminders.walletCurrency = nil
            }
            synchronizedConfigurations[configIndex].providerRegion = envelope.providerRegion
            if provider == .gitKraken { synchronizedConfigurations[configIndex].organizationID = envelope.metadata["organizationID"] }
            if provider == .alibabaTokenPlan { synchronizedConfigurations[configIndex].tokenPlanSite = envelope.metadata["consoleSite"].flatMap(AlibabaTokenPlanSite.init(rawValue:)) }
            synchronizedConfigurations[configIndex].modifiedAt = Date()
        }
    }

    private func snapshotMatchesIdentity(_ state: AccountQuotaState, identity: String) -> Bool {
        guard let snapshot = state.snapshot, snapshot.accountID == state.id else { return false }
        // The reading's explicit provenance wins over an outer state tag. The
        // state tag remains the compatibility fallback for older scoped readings.
        return (snapshot.sourceCredentialFingerprint ?? state.credentialIdentity) == identity
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
                if let provider = synchronizedConfigurations.first(where: { $0.id == accountID })?.account.provider {
                    try await credentialStore.deleteCredential(for: accountID, provider: provider)
                } else { try await credentialStore.deleteCredential(for: accountID) }
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
