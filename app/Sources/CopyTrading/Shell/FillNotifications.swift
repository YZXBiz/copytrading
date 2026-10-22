import DesktopCore
import Foundation
import UserNotifications

/// Says each copied order as a macOS notification with the system sound: when it goes to the broker
/// ("Buying 9.804 shares of GFS at up to $51.00") and when it fills ("Bought 9.804 shares of GFS at
/// $48.49"), then whose post it came from and which account. Permission is asked when the app
/// opens. The owner turns it off under Settings → While Copying.
@MainActor
enum FillNotifications {
    static let settingKey = "notifications.fills"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Asks macOS once whether CopyTrading may notify; later calls return at once.
    static func requestPermission() {
        guard isOn else { return }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    static func post(_ news: FillWatch.News, directory: GuruDirectory) {
        guard isOn else { return }
        let center = UNUserNotificationCenter.current()
        let said = news.sent.map { ($0, sentTitle($0), "sent") } + news.filled.map { ($0, title($0), "fill") }
        let requests = said.map { fill, heading, kind in
            let content = UNMutableNotificationContent()
            content.title = heading
            content.body = origin(fill, directory: directory)
            content.sound = .default
            content.threadIdentifier = fill.accountID
            return UNNotificationRequest(identifier: "\(kind)-\(fill.clientID)", content: content, trigger: nil)
        }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    /// "From Zhao's post · paper", "Your sale · paper", or "Into paper".
    static func origin(_ fill: FillWatch.Fill, directory: GuruDirectory) -> String {
        if fill.byOwner { return L10n.string("Your sale · %@", fill.accountID) }
        return directory.name(for: fill.guruID).map { L10n.string("From %@'s post · %@", $0, fill.accountID) }
            ?? L10n.string("Into %@", fill.accountID)
    }

    private static func sentTitle(_ fill: FillWatch.Fill) -> String {
        let shares = Humanize.shares(fill.shares)
        let stock = fill.symbol
        guard let price = fill.price else {
            return fill.side == "sell"
                ? L10n.string("Selling %@ of %@", shares, stock) : L10n.string("Buying %@ of %@", shares, stock)
        }
        let limit = price.formatted(.currency(code: "USD"))
        return fill.side == "sell"
            ? L10n.string("Selling %@ of %@ at %@ or more", shares, stock, limit)
            : L10n.string("Buying %@ of %@ at up to %@", shares, stock, limit)
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
