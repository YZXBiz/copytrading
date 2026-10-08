import DesktopCore
import Foundation

extension AccountFeedItem {
    /// What happened, as a sentence: "You sold 1 share of PM at $201.70".
    @MainActor var sentence: String {
        let stock = symbol ?? "—"
        let count = shareCount
        let at = money(price)
        let buying = side != "sell"
        switch kind {
        case "bought" where source == "you":
            return L10n.string("You bought %@ of %@ at %@", count, stock, at)
        case "bought":
            return L10n.string("Bought %@ of %@ at %@", count, stock, at)
        case "sold" where source == "you":
            return L10n.string("You sold %@ of %@ at %@", count, stock, at)
        case "sold":
            return L10n.string("Sold %@ of %@ at %@", count, stock, at)
        case "cancelled":
            return buying
                ? L10n.string("Buy of %@ of %@ at %@ cancelled", count, stock, at)
                : L10n.string("Sale of %@ of %@ at %@ cancelled", count, stock, at)
        case "expired":
            return buying
                ? L10n.string("Buy of %@ of %@ at %@ expired unfilled", count, stock, at)
                : L10n.string("Sale of %@ of %@ at %@ expired unfilled", count, stock, at)
        case "rejected":
            return buying
                ? L10n.string("Alpaca rejected a buy of %@ of %@", count, stock)
                : L10n.string("Alpaca rejected a sale of %@ of %@", count, stock)
        case "paused": return L10n.string("You paused new buys")
        case "resumed": return L10n.string("You resumed new buys")
        case "settled": return L10n.string("You settled the holdings review for %@", stock)
        default: return L10n.string(Humanize.code(kind))
        }
    }

    /// Who made it happen: the guru whose post was copied, or "manual" for the owner.
    @MainActor func origin(_ directory: GuruDirectory) -> String {
        source == "you" ? L10n.string("manual") : directory.name(for: guruID) ?? L10n.string("Copied post")
    }

    /// To the second today, since trades land seconds apart; the date on older rows.
    @MainActor var time: String {
        guard let date = Humanize.date(at) else { return "—" }
        return AppTime.calendar.isDateInToday(date)
            ? date.formatted(AppTime.style(.dateTime.hour().minute().second()))
            : Humanize.postTime(date)
    }

    var isTrade: Bool { kind == "bought" || kind == "sold" }

    var tone: StatusTone {
        switch kind {
        case "bought", "sold": .positive
        case "rejected": .critical
        case "cancelled", "expired": .inactive
        default: .neutral
        }
    }

    @MainActor private var shareCount: String {
        guard let value = Decimal(engine: shares) else { return L10n.string("some shares") }
        let number = value.formatted()
        return value == 1 ? L10n.string("%@ share", number) : L10n.string("%@ shares", number)
    }

    private func money(_ value: String?) -> String {
        Decimal(engine: value)?.formatted(.currency(code: "USD")) ?? "—"
    }
}
