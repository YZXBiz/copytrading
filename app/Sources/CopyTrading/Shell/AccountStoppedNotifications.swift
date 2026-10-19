import Foundation
import UserNotifications

/// Says an account stopped copying on its own as a macOS notification with the system sound, once
/// per stop. It is not tied to the fills switch under Settings → While Copying: someone who
/// silenced fills still needs to hear that money stopped being copied.
@MainActor
enum AccountStoppedNotifications {
    static func post(_ accountIDs: [String]) {
        let requests = accountIDs.map { accountID in
            let content = UNMutableNotificationContent()
            content.title = AccountStoppedText.title(accountID)
            content.body = AccountStoppedText.body
            content.sound = .default
            content.threadIdentifier = "account-stopped"
            return UNNotificationRequest(identifier: "stopped-\(accountID)-\(UUID().uuidString)", content: content, trigger: nil)
        }
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for request in requests {
                try? await center.add(request)
            }
        }
    }
}
