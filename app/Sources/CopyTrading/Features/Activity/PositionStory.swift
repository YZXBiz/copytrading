import DesktopCore
import Foundation

/// The life of the holding a post's buy opened or joined, start to finish: every buy into it, from
/// this post or others, and every sale of it, copied or the owner's own, in time order, with what it
/// made once it is all sold (ADR-0010). Read from the account's activity rows that name its lot.
struct PositionStory: Equatable {
    enum Kind: Equatable {
        /// The buy that opened the holding.
        case bought
        /// A later buy that joined it.
        case added
        /// A sale of part of it.
        case sold
        /// The sale that emptied it.
        case soldAll
    }

    struct Step: Equatable {
        let kind: Kind
        let shares: Decimal
        let price: Decimal
        let amount: Decimal
        let at: Date
        /// The owner sold it by hand; otherwise a guru's post was copied.
        let byOwner: Bool
        let guruID: String?
        let messageID: String?
        /// The buy this post made, marked in the story.
        let isThisPost: Bool
    }

    let symbol: String
    let steps: [Step]
    /// What the holding made or lost once it is all sold; nil while shares remain.
    let result: Decimal?

    /// Shares closer than this count as all sold, since sizes are kept to the millionth.
    private static let tolerance = Decimal(string: "0.000001")!

    /// The story of the holding `sourceID`'s buy belongs to, or nil when that holding is just the
    /// one buy with nothing sold, which the order's own result already says.
    init?(post sourceID: String, feed: [AccountFeedItem]) {
        let trades = feed.filter { ($0.kind == "bought" || $0.kind == "sold") && $0.lotID != nil }
        guard
            let lotID = trades.first(where: { $0.messageID == sourceID && $0.source != "you" })?.lotID
                ?? trades.first(where: { $0.messageID == sourceID })?.lotID
        else { return nil }
        let rows =
            trades
            .filter { $0.lotID == lotID }
            .compactMap { row -> (row: AccountFeedItem, at: Date, shares: Decimal, price: Decimal)? in
                guard let at = Self.date(row.at), let shares = Decimal(string: row.shares ?? ""),
                    let price = Decimal(string: row.price ?? "")
                else { return nil }
                return (row, at, shares, price)
            }
            .sorted { ($0.at, $0.row.sequence) < ($1.at, $1.row.sequence) }
        guard rows.count >= 2, let symbol = rows.first?.row.symbol else { return nil }
        var held = Decimal(0)
        var bought = Decimal(0)
        var sold = Decimal(0)
        var steps: [Step] = []
        for (row, at, shares, price) in rows {
            let amount = Decimal(string: row.amount ?? "") ?? shares * price
            let kind: Kind
            if row.kind == "bought" {
                kind = steps.contains { $0.kind == .bought || $0.kind == .added } ? .added : .bought
                held += shares
                bought += amount
            } else {
                kind = shares >= held - Self.tolerance ? .soldAll : .sold
                held -= shares
                sold += amount
            }
            steps.append(
                Step(
                    kind: kind, shares: shares, price: price, amount: amount, at: at, byOwner: row.source == "you",
                    guruID: row.guruID, messageID: row.messageID,
                    isThisPost: row.kind == "bought" && row.messageID == sourceID && row.source != "you"))
        }
        self.symbol = symbol
        self.steps = steps
        result = held <= Self.tolerance && sold > 0 ? sold - bought : nil
    }

    /// The engine's ISO 8601 times, with or without fractional seconds.
    private static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
