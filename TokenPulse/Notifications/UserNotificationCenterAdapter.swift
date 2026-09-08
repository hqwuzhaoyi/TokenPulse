import Foundation
import UserNotifications

protocol NotificationApplying: Sendable {
    @MainActor func configure()
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func apply(_ operations: [NotificationOperation]) async throws
}

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

enum NotificationAdapterError: Error, Equatable {
    case authorizationRequired
}

struct UserNotificationCenterAdapter: NotificationApplying, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let foregroundDelegate: ForegroundNotificationDelegate

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        foregroundDelegate = ForegroundNotificationDelegate()
    }

    @MainActor
    func configure() {
        center.delegate = foregroundDelegate
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func apply(_ operations: [NotificationOperation]) async throws {
        guard !operations.isEmpty else { return }
        let requiresAuthorization = operations.contains { operation in
            switch operation {
            case .deliver, .schedule: true
            case .cancel: false
            }
        }
        if requiresAuthorization {
            guard await authorizationStatus() == .authorized else {
                throw NotificationAdapterError.authorizationRequired
            }
        }
        for operation in operations {
            switch operation {
            case let .deliver(notification):
                try await center.add(request(for: notification, trigger: nil))
            case let .schedule(notification, date):
                let components = Calendar.current.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                    from: date
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(request(for: notification, trigger: trigger))
            case let .cancel(identifiers):
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }

    private func request(for notification: ReminderNotification,
                         trigger: UNNotificationTrigger?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = ["kind": notification.kind.rawValue]
        return UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger
        )
    }
}

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
