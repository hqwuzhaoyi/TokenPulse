import Foundation

#if os(iOS)
import BackgroundTasks

private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let task: BGAppRefreshTask
    private var completed = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

final class IOSBackgroundRefreshAdapter: @unchecked Sendable {
    typealias RefreshOperation = @Sendable () async -> Void

    private let identifier: String

    init(identifier: String = PlatformConstants.backgroundRefreshIdentifier) {
        self.identifier = identifier
    }

    func register(operation: @escaping RefreshOperation) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let completion = BackgroundTaskCompletion(task: refreshTask)
            let work = Task {
                await operation()
                completion.finish(success: !Task.isCancelled)
            }
            refreshTask.expirationHandler = {
                work.cancel()
                completion.finish(success: false)
            }
        }
    }

    func schedule(earliestBeginDate: Date = Date().addingTimeInterval(30 * 60)) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
}
#endif

#if os(watchOS)
import WatchKit

@MainActor
struct WatchBackgroundRefreshAdapter: Sendable {
    func schedule(preferredDate: Date = Date().addingTimeInterval(30 * 60)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKApplication.shared().scheduleBackgroundRefresh(
                withPreferredDate: preferredDate,
                userInfo: nil
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
