import DesktopCore
import Foundation

/// One trade the owner is about to send by hand, as plain choices: buy or sell, which stock, how
/// much, and at what price. `value` is the engine's manual instruction, unchanged.
struct ManualInstructionDraft: Identifiable, Equatable {
    /// A sell's share of what is held: a quarter, a third, half, three quarters, or all of it.
    static let sellShares = ["0.25", "\(Decimal(1) / Decimal(3))", "0.5", "0.75", "1"]
    /// A buy's share of the full position; empty buys the full position.
    static let buySizes = ["\(Decimal(1) / Decimal(6))", "0.25", "\(Decimal(1) / Decimal(3))", "0.5", ""]

    let id = UUID()
    var isSell = false
    var symbol = ""
    /// The price the post named; empty when it named none.
    var postPrice = ""
    /// The price sent: the post's, the market's, or one the owner typed. Empty on a sell sells at
    /// the market, just under the live bid (ADR-0007).
    var price = ""
    /// A sell's buy price; empty sells from every buy of the stock (ADR-0010).
    var entryPrice = ""
    /// A buy's share of the full position (empty buys the full position), or the share to sell
    /// ("1" sells all of it).
    var fraction = ""
    var exitBasis: String?

    init() {}

    /// A call the engine read or held back, ready for the owner to copy (ADR-0007).
    init(call: SourceInstruction) {
        let action = ManualInstructionAction(rawValue: call.action) ?? .buy
        isSell = action != .buy
        symbol = call.symbol
        postPrice = call.price ?? ""
        price = call.price ?? ""
        entryPrice = call.entryPrice ?? ""
        fraction = action == .close ? "1" : call.fraction ?? ""
        exitBasis = call.exitBasis
    }

    var action: ManualInstructionAction {
        guard isSell else { return .buy }
        return Decimal(string: fraction.trimmed) == 1 ? .close : .reduce
    }

    /// A sell with no price sells at the market.
    var sellsAtMarket: Bool { isSell && price.trimmed.isEmpty }

    var isValid: Bool {
        guard !symbol.trimmed.isEmpty else { return false }
        guard sellsAtMarket || Decimal(string: price.trimmed).map({ $0 > 0 }) == true else { return false }
        return !isSell || Decimal(string: fraction.trimmed).map { $0 > 0 && $0 <= 1 } == true
    }

    var value: ManualInstruction {
        ManualInstruction(
            action: action,
            symbol: symbol.trimmed.uppercased(),
            price: sellsAtMarket ? nil : price.trimmed,
            entryPrice: isSell ? entryPrice.trimmed.nilIfEmpty : nil,
            fraction: action == .close ? "1" : fraction.trimmed.nilIfEmpty,
            exitBasis: isSell ? exitBasis : nil
        )
    }

    /// Two share strings name the same amount: "0.5" and "0.50", or a third written two ways.
    static func sameShare(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = Decimal(string: lhs.trimmed), let right = Decimal(string: rhs.trimmed) else {
            return lhs.trimmed == rhs.trimmed
        }
        return abs(NSDecimalNumber(decimal: left - right).doubleValue) < 1e-9
    }
}
