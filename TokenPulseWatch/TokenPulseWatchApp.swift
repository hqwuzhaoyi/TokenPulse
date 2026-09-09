import SwiftUI
import WatchKit

@MainActor
final class TokenPulseWatchDelegate: NSObject, WKApplicationDelegate, ObservableObject {
    let runtime = AppRuntime()

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for backgroundTask in backgroundTasks {
            guard backgroundTask is WKApplicationRefreshBackgroundTask else {
                backgroundTask.setTaskCompletedWithSnapshot(false)
                continue
            }
            let work = Task { @MainActor [runtime] in
                await runtime.refresh()
                await runtime.scheduleBackgroundRefresh()
                backgroundTask.setTaskCompletedWithSnapshot(true)
            }
            backgroundTask.expirationHandler = {
                work.cancel()
                backgroundTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main
struct TokenPulseWatchApp: App {
    @WKApplicationDelegateAdaptor(TokenPulseWatchDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchAccountPagesView(runtime: delegate.runtime, monitor: delegate.runtime.monitor)
                .task {
                    _ = await delegate.runtime.notifications.requestAuthorization()
                    await delegate.runtime.start()
                }
        }
    }
}
