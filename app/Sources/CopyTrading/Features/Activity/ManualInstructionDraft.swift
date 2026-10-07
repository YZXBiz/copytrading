import DesktopCore
import Foundation

struct ManualInstructionDraft: Identifiable {
    let id = UUID()
    var action: ManualInstructionAction = .buy
    var symbol = ""
    var price = ""
    /// A sell's buy price; empty sells from every buy of the stock (ADR-0010).
    var entryPrice = ""
    /// A buy's share of the full position (empty buys the full position), or the share to sell.
    var fraction = ""
    var exitBasis: String?

    init() {}

    /// A call the engine read or held back, ready for the owner to copy (ADR-0007).
    init(call: SourceInstruction) {
        action = ManualInstructionAction(rawValue: call.action) ?? .buy
        symbol = call.symbol
        price = call.price
        entryPrice = call.entryPrice ?? ""
        fraction = call.fraction ?? ""
        exitBasis = call.exitBasis
    }

    var isValid: Bool {
        !symbol.trimmed.isEmpty && !price.trimmed.isEmpty
            && (action != .reduce || !fraction.trimmed.isEmpty)
    }

    var value: ManualInstruction {
        ManualInstruction(
            action: action,
            symbol: symbol.trimmed.uppercased(),
            price: price.trimmed,
            entryPrice: action == .buy ? nil : entryPrice.trimmed.nilIfEmpty,
            fraction: action == .close ? "1" : fraction.trimmed.nilIfEmpty,
            exitBasis: action == .buy ? nil : exitBasis
        )
    }
}
