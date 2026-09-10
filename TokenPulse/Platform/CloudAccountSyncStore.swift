import Foundation
import Combine

enum CloudSyncError: LocalizedError {
    case unavailable
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .unavailable: "无法提交 iCloud 同步请求，请检查 iCloud 登录和同步权限。"
        case .invalidPayload: "无法读取 iCloud 账号数据，请确认两端应用版本一致。"
        }
    }
}

@MainActor
final class CloudSyncSettings: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var lastRequestedAt: Date?
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var revision = 0

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        isEnabled = defaults.object(forKey: "cloudSyncEnabled") as? Bool ?? true
        lastRequestedAt = defaults.object(forKey: "cloudSyncLastRequestedAt") as? Date
        lastReceivedAt = defaults.object(forKey: "cloudSyncLastReceivedAt") as? Date
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        revision += 1
        errorMessage = nil
        defaults.set(enabled, forKey: "cloudSyncEnabled")
    }

    func perform(_ operation: () async throws -> Void) async {
        guard isEnabled, !isSyncing else { return }
        let currentRevision = revision
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            try await operation()
            guard isEnabled, revision == currentRevision, !Task.isCancelled else { return }
            lastRequestedAt = now()
            defaults.set(lastRequestedAt, forKey: "cloudSyncLastRequestedAt")
        } catch is CancellationError {
            return
        } catch {
            guard isEnabled, revision == currentRevision else { return }
            report(error)
        }
    }

    func received() {
        guard isEnabled else { return }
        lastReceivedAt = now()
        defaults.set(lastReceivedAt, forKey: "cloudSyncLastReceivedAt")
    }

    func report(_ error: Error) {
        errorMessage = (error as? CloudSyncError)?.errorDescription ?? "同步失败，请稍后重试。"
    }
}

struct PlatformAccountPayload: Codable, Equatable, Sendable {
    var configurations: [AccountConfiguration]
    var states: [AccountQuotaState]
    var ledger: ReminderLedger
}

actor ICloudSyncRuntime {
    typealias IncomingHandler = @Sendable (PlatformAccountPayload, Bool) async -> Void

    private let store: NSUbiquitousKeyValueStore
    private let key: String
    private let onIncoming: IncomingHandler
    private let onError: @Sendable (CloudSyncError) async -> Void
    private var observer: NSObjectProtocol?

    init(
        store: NSUbiquitousKeyValueStore = .default,
        key: String = "platform.accountPayload",
        onIncoming: @escaping IncomingHandler,
        onError: @escaping @Sendable (CloudSyncError) async -> Void = { _ in }
    ) {
        self.store = store
        self.key = key
        self.onIncoming = onIncoming
        self.onError = onError
    }

    func start() async throws {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                queue: nil
            ) { [weak self] notification in
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                Task {
                    guard let self else { return }
                    if reason == NSUbiquitousKeyValueStoreQuotaViolationChange
                        || reason == NSUbiquitousKeyValueStoreAccountChange {
                        await self.onError(.unavailable)
                        return
                    }
                    guard keys?.contains(self.key) != false else { return }
                    do { try await self.deliverCurrentPayload(isExternalUpdate: true) }
                    catch { await self.onError(.invalidPayload) }
                }
            }
        }
        guard store.synchronize() else { throw CloudSyncError.unavailable }
        try await deliverCurrentPayload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func push(
        configurations: [AccountConfiguration],
        states: [AccountQuotaState],
        ledger: ReminderLedger
    ) async throws {
        guard observer != nil else { return }
        let local = PlatformAccountPayload(
            configurations: configurations,
            states: states,
            ledger: ledger
        )
        let merged: PlatformAccountPayload
        if let data = store.data(forKey: key) {
            guard let cloud = try? JSONDecoder().decode(PlatformAccountPayload.self, from: data) else {
                throw CloudSyncError.invalidPayload
            }
            merged = Self.merge(local, cloud)
        } else {
            merged = local
        }
        store.set(try JSONEncoder().encode(merged), forKey: key)
        guard store.synchronize() else { throw CloudSyncError.unavailable }
    }

    nonisolated static func merge(
        _ local: PlatformAccountPayload,
        _ cloud: PlatformAccountPayload
    ) -> PlatformAccountPayload {
        let configurations = mergeConfigurations(local.configurations, cloud.configurations)
        let deletedIDs = Set(configurations.filter { $0.deletedAt != nil }.map(\.id))
        return PlatformAccountPayload(
            configurations: configurations,
            states: mergeStates(local.states, cloud.states).filter { !deletedIDs.contains($0.id) },
            ledger: local.ledger.merging(cloud.ledger)
        )
    }

    private func deliverCurrentPayload(isExternalUpdate: Bool = false) async throws {
        guard observer != nil, let data = store.data(forKey: key) else { return }
        guard let payload = try? JSONDecoder().decode(PlatformAccountPayload.self, from: data) else {
            throw CloudSyncError.invalidPayload
        }
        await onIncoming(payload, isExternalUpdate)
    }

    nonisolated private static func mergeConfigurations(
        _ lhs: [AccountConfiguration],
        _ rhs: [AccountConfiguration]
    ) -> [AccountConfiguration] {
        var byID = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
        for candidate in rhs {
            if byID[candidate.id] == nil || candidate.deletedAt != nil
                || (byID[candidate.id]?.deletedAt == nil
                    && candidate.modifiedAt > (byID[candidate.id]?.modifiedAt ?? .distantPast)) {
                byID[candidate.id] = candidate
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    nonisolated private static func mergeStates(
        _ lhs: [AccountQuotaState],
        _ rhs: [AccountQuotaState]
    ) -> [AccountQuotaState] {
        var byID = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
        for candidate in rhs {
            guard let current = byID[candidate.id] else {
                byID[candidate.id] = candidate
                continue
            }
            if candidate.snapshot?.collectedAt ?? .distantPast
                > current.snapshot?.collectedAt ?? .distantPast {
                byID[candidate.id] = candidate
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
