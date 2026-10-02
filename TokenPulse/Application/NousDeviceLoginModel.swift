import Combine
import Foundation

@MainActor
final class NousDeviceLoginModel: ObservableObject {
    @Published private(set) var session: ProviderLoginSession?
    @Published private(set) var message: String?
    @Published private(set) var running = false
    private var runID = UUID()
    private var task: Task<Void, Never>?
    private let controller: ProviderAuthenticationController
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    init(controller: ProviderAuthenticationController = ProviderAuthenticationController(),
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds(max($0, 1))) }) {
        self.controller = controller
        self.sleep = sleep
    }
    @discardableResult
    func start(accountID: UUID, expectedIdentity: String, completion: @escaping (String) -> Void) -> Task<Void, Never> {
        cancel()
        let run = runID
        running = true; message = nil; session = nil
        let work = Task { @MainActor in
            defer { if runID == run { running = false; task = nil } }
            do {
                guard runID == run, !Task.isCancelled else { return }
                let pending = try await controller.beginLogin(provider: .nousPortal, accountID: accountID)
                guard runID == run, !Task.isCancelled else { return }
                session = pending
                while !Task.isCancelled {
                    let progress = try await controller.continueLogin(pending)
                    guard runID == run, !Task.isCancelled else { return }
                    switch progress {
                    case .pending(let interval): try await sleep(interval)
                    case .completed(let value):
                        let envelope = try ProviderCredentialEnvelope.decode(value, expectedProvider: .nousPortal)
                        guard envelope.sourceCredentialIdentity == expectedIdentity else {
                            message = "请授权与此服务账号一致的 Nous 用户和组织。"
                            return
                        }
                        completion(value)
                        return
                    }
                }
            } catch {
                guard runID == run, !Task.isCancelled else { return }
                message = (error as? RefreshFailure)?.displayName ?? "授权尚未完成，请重试。"
            }
        }
        task = work
        return work
    }
    func cancel() {
        runID = UUID()
        task?.cancel(); task = nil
        running = false
    }
}
