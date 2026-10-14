import DesktopCore
import Foundation
import UserNotifications

/// Says an agent's request is waiting for the owner as a macOS notification, because its approval
/// sheet lives inside the window and is easy to miss from another app. Clicking it opens CopyTrading
/// on the sheet. The assistant's own requests are not announced: the owner is already looking.
@MainActor
enum AgentRequestNotifications {
    static func post(_ proposal: AgentProposal) {
        let content = UNMutableNotificationContent()
        content.title = proposal.approvalHeading
        content.body = proposal.summary
        content.sound = .default
        content.threadIdentifier = "agent-requests"
        let request = UNNotificationRequest(identifier: "agent-\(proposal.id)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }
}
