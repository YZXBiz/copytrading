import DesktopCore
import Foundation
import UserNotifications

/// Says each copied fill as a macOS notification with the system sound: "Bought 0.885 shares of
/// WMT at $110.75", then whose post it came from and which account. Asks for permission the first
/// time there is something to say. The owner turns it off under Settings → While Copying.
@MainActor
enum FillNotifications {
    static let settingKey = "notifications.fills"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static func post(_ fills: [FillWatch.Fill], directory: GuruDirectory) {
        guard isOn else { return }
        let center = UNUserNotificationCenter.current()
        let requests = fills.map { fill in
            let content = UNMutableNotificationContent()
            content.title = title(fill)
            let guru = directory.name(for: fill.guruID)
            content.body =
                guru.map { L10n.string("From %@'s post · %@", $0, fill.accountID) }
                ?? L10n.string("Into %@", fill.accountID)
            content.sound = .default
            content.threadIdentifier = fill.accountID
            return UNNotificationRequest(identifier: "fill-\(fill.clientID)", content: content, trigger: nil)
        }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    private static func title(_ fill: FillWatch.Fill) -> String {
        let shares = Humanize.shares(fill.shares)
        let stock = fill.symbol
        guard let price = fill.price else {
            return fill.side == "sell"
                ? L10n.string("Sold %@ of %@", shares, stock) : L10n.string("Bought %@ of %@", shares, stock)
        }
        let at = price.formatted(.currency(code: "USD"))
        return fill.side == "sell"
            ? L10n.string("Sold %@ of %@ at %@", shares, stock, at) : L10n.string("Bought %@ of %@ at %@", shares, stock, at)
    }
}
