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
        case "settled": return settledSentence(stock: stock, count: count)
        case "limits_changed":
            return L10n.string("You changed limits: %@", changes.map(Self.phrase).joined(separator: L10n.string(", ")))
        default: return L10n.string(Humanize.code(kind))
        }
    }

    /// A settled holdings count, said as what happened at the broker: shares bought or sold
    /// outside CopyTrading and how they now count, or the owner's own answer.
    @MainActor private func settledSentence(stock: String, count: String) -> String {
        switch reason {
        case "owner_bought_outside":
            L10n.string("You bought %@ of %@ outside CopyTrading. They count as yours; CopyTrading won't sell them.", count, stock)
        case "owner_sold_own_shares":
            L10n.string("You sold %@ of your own %@ outside CopyTrading. The count is updated.", count, stock)
        case "owner_sold_copied_shares":
            L10n.string("%@ of copied %@ were sold outside CopyTrading. The oldest buys count as sold.", count, stock)
        case "broker_matches_again":
            L10n.string("%@ at Alpaca matches CopyTrading's count again", stock)
        default:
            L10n.string("You settled the holdings review for %@", stock)
        }
    }

    /// Who made it happen, under the row's time: the guru whose post was copied, or "You".
    @MainActor func credit(_ directory: GuruDirectory) -> String {
        source == "you" ? L10n.string("You") : directory.name(for: guruID) ?? L10n.string("Copied post")
    }

    /// The clock to the second, since trades land seconds apart; the day is the label above.
    @MainActor var time: String {
        Humanize.date(at)?.formatted(AppTime.style(.dateTime.hour().minute().second())) ?? "—"
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

    /// "per order $200 → $500".
    @MainActor private static func phrase(_ change: AccountLimitChange) -> String {
        let (name, unit) = setting(change.setting)
        return L10n.string("%@ %@ → %@", name, value(change.before, unit), value(change.after, unit))
    }

    private enum Unit { case dollars, seconds, percent, count, onOff }

    @MainActor private static func setting(_ code: String) -> (String, Unit) {
        switch code {
        case "max_order_usd": (L10n.string("per order"), .dollars)
        case "max_symbol_usd": (L10n.string("per stock"), .dollars)
        case "max_total_usd": (L10n.string("total exposure"), .dollars)
        case "daily_loss_cap_usd": (L10n.string("daily loss cap"), .dollars)
        case "max_entries_per_day": (L10n.string("entries per day"), .count)
        case "max_signal_age_seconds": (L10n.string("signal age"), .seconds)
        case "order_timeout_seconds": (L10n.string("order timeout"), .seconds)
        case "poll_seconds": (L10n.string("check interval"), .seconds)
        case "max_above_signal_pct": (L10n.string("above signal price"), .percent)
        case "max_below_signal_pct": (L10n.string("below signal price"), .percent)
        case "extended_hours": (L10n.string("extended hours"), .onOff)
        case "overnight": (L10n.string("overnight"), .onOff)
        case "copy_exits": (L10n.string("copy exits"), .onOff)
        case "approve_orders": (L10n.string("ask before orders"), .onOff)
        default: (L10n.string(Humanize.code(code)).lowercased(), .count)
        }
    }

    @MainActor private static func value(_ text: String, _ unit: Unit) -> String {
        guard unit != .onOff else { return L10n.string(text == "true" ? "on" : "off") }
        guard let number = Decimal(engine: text) else { return text }
        switch unit {
        case .dollars: return number.formatted(.currency(code: "USD"))
        case .seconds: return L10n.string("%@ s", number.formatted())
        case .percent: return L10n.string("%@%%", number.formatted())
        case .count, .onOff: return number.formatted()
        }
    }
}
