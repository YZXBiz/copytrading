import DesktopCore
import Foundation

/// Why a sell naming a buy price has nothing to sell (ADR-0010), from what came of the guru's buy
/// at that price: "The $83.35 buy on Oct 23 wasn't made. Your daily entry limit was reached."
@MainActor
enum NamedBuyText {
    /// The first held sell's reason across the post's accounts, or nil when no sell is held for
    /// its buy price.
    static func sentence(in source: SourceActivity) -> String? {
        source.destinations.lazy.compactMap { destination in
            destination.namedBuys.first.flatMap { sentence($0, in: source) }
        }.first
    }

    static func sentence(_ named: NamedBuy, in source: SourceActivity) -> String? {
        guard source.instructions.indices.contains(named.part),
            let price = Decimal(engine: source.instructions[named.part].entryPrice)
        else { return nil }
        let buy = price.formatted(.currency(code: "USD"))
        guard let posted = Humanize.date(named.postedAt), let outcome = named.outcome else {
            return L10n.sentence(L10n.string("The guru's %@ buy never reached this account", buy))
        }
        let day = posted.formatted(AppTime.style(.dateTime.month(.abbreviated).day()))
        switch outcome {
        case "sold":
            return L10n.sentence(L10n.string("The %1$@ buy on %2$@ is already sold", buy, day))
        case "not_filled":
            return L10n.sentence(L10n.string("The %1$@ buy on %2$@ never filled", buy, day))
        default:
            return L10n.sentences([
                L10n.sentence(L10n.string("The %1$@ buy on %2$@ wasn't made", buy, day)),
                L10n.sentence(Reason.text(outcome)),
            ])
        }
    }
}
