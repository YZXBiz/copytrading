import DesktopCore
import Foundation

struct ManualInstructionDraft: Identifiable {
    let id = UUID()
    var action: ManualInstructionAction = .buy
    var symbol = ""
    var price = ""
    var entryPrice = ""
    var fraction = ""

    var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (action == .buy || !entryPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (action == .buy || action == .close || !fraction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var value: ManualInstruction {
        ManualInstruction(
            action: action,
            symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            price: price.trimmingCharacters(in: .whitespacesAndNewlines),
            entryPrice: action == .buy ? nil : entryPrice.trimmingCharacters(in: .whitespacesAndNewlines),
            fraction: action == .buy ? nil : action == .close ? "1" : fraction.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
