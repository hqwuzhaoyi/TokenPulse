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
            WatchRootView(runtime: delegate.runtime)
        }
    }
}

private struct WatchRootView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        WatchAccountPagesView(runtime: runtime, monitor: runtime.monitor)
            .id(runtime.isDemoMode)
            .task {
                _ = await runtime.notifications.requestAuthorization()
                await runtime.start()
            }
    }
}
