import Foundation
import UserNotifications

/// Says that CopyTrading came back with copying paused as a macOS notification, so it is seen even
/// when the window is hidden or another app is in front. Clicking it opens CopyTrading, where the
/// banner starts copying.
@MainActor
enum CopyingStoppedNotification {
    static func post() {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("Copying is paused")
        content.body = L10n.string("Copying paused when CopyTrading quit. Open CopyTrading and press Start Copying.")
        content.sound = .default
        content.threadIdentifier = "copying-stopped"
        let request = UNNotificationRequest(identifier: "copying-stopped", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }
}
