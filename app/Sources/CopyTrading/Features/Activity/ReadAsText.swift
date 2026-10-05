import DesktopCore
import Foundation

/// The "Read as" part of an Activity card (ADR-0007): what kind of post it was, one line per call,
/// and a few facts, written by the app from the reading so they read in the owner's language.
@MainActor
enum ReadAsText {
    static func kind(_ reading: PostReading) -> String {
        switch reading {
        case .tradeMade: L10n.string("a trade the guru made")
        case .instruction: L10n.string("an instruction")
        case .conditional: L10n.string("a condition")
        case .suggestion: L10n.string("a suggestion")
        case .commentary: L10n.string("talk, nothing to trade")
        case .unclear: L10n.string("unclear")
        }
    }

    /// One line per call; a post with no calls says what it was in the reader's own summary.
    static func lines(_ reading: PostReading) -> [String] {
        switch reading {
        case .commentary(let summary): [summary]
        case .unclear: [L10n.string("The reader couldn't tell what this post means.")]
        default: reading.calls.map(line)
        }
    }

    static func line(_ call: ReadCall) -> String {
        switch call {
        case .buy(let buy):
            L10n.string("Buy %@ %@%@.", buy.stock.ticker, price(buy.price), size(buy.size))
        case .sell(let sell):
            if case .lot(let buyPrice, _) = sell.sellFrom {
                L10n.string(
                    "Sell %@ of the %@ bought at %@, %@.", share(sell.share), sell.stock.ticker,
                    Humanize.dollars(buyPrice), price(sell.price))
            } else {
                L10n.string("Sell %@ of %@, %@.", share(sell.share), sell.stock.ticker, price(sell.price))
            }
        }
    }

    static func facts(_ call: ReadCall) -> [String] {
        switch call {
        case .buy(let buy):
            [L10n.string("Buy"), buy.stock.ticker, priceFact(buy.price), sizeFact(buy.size)]
        case .sell(let sell):
            [
                L10n.string("Sell"), sell.stock.ticker, priceFact(sell.price), shareFact(sell.share),
                {
                    if case .lot(let buyPrice, _) = sell.sellFrom {
                        return L10n.string("from the %@ buy", Humanize.dollars(buyPrice))
                    }
                    return L10n.string("no buy named")
                }(),
            ]
        }
    }

    private static func price(_ price: ReadPrice) -> String {
        switch price {
        case .exact(let value, _): L10n.string("at %@", Humanize.dollars(value))
        case .range(let low, let high, _, _): L10n.string("between %@ and %@", Humanize.dollars(low), Humanize.dollars(high))
        case .atMarket: L10n.string("at the market price")
        case .notGiven: L10n.string("with no price given")
        }
    }

    private static func size(_ size: ReadSize) -> String {
        switch size {
        case .fraction(let value, _): L10n.string(", %@ of a full position", portion(value))
        case .batch(let number, _): L10n.string(", batch %lld", Int64(number))
        case .notGiven: ""
        }
    }

    private static func share(_ share: ReadShare) -> String {
        switch share {
        case .all: L10n.string("all")
        case .fraction(let value, _): portion(value)
        }
    }

    /// A share as a person says it: "half", "a third", "a sixth", else "1/5".
    static func portion(_ value: String) -> String {
        switch Humanize.fraction(value) {
        case "1": L10n.string("all")
        case "1/2": L10n.string("half")
        case "1/3": L10n.string("a third")
        case "1/4": L10n.string("a quarter")
        case "1/6": L10n.string("a sixth")
        case let other: other
        }
    }

    private static func priceFact(_ price: ReadPrice) -> String {
        switch price {
        case .exact(let value, _): Humanize.dollars(value)
        case .range(let low, let high, _, _): "\(Humanize.dollars(low))–\(Humanize.dollars(high))"
        case .atMarket: L10n.string("market price")
        case .notGiven: L10n.string("no price")
        }
    }

    private static func sizeFact(_ size: ReadSize) -> String {
        switch size {
        case .fraction(let value, _): Humanize.fraction(value)
        case .batch(let number, _): L10n.string("batch %lld", Int64(number))
        case .notGiven: L10n.string("no size")
        }
    }

    private static func shareFact(_ share: ReadShare) -> String {
        switch share {
        case .all: L10n.string("all")
        case .fraction(let value, _): Humanize.fraction(value)
        }
    }
}
