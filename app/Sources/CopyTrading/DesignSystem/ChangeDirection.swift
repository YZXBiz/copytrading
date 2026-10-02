import SwiftUI

/// Up, down, or flat; each has its own symbol so change never depends on color alone.
enum ChangeDirection {
    case up
    case down
    case flat

    init(_ value: Decimal) {
        self = value > 0 ? .up : value < 0 ? .down : .flat
    }

    var symbol: String {
        switch self {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "minus"
        }
    }

    var color: Color {
        switch self {
        case .up: .green
        case .down: .red
        case .flat: .secondary
        }
    }

    @MainActor
    func spoken(_ value: Decimal) -> String {
        let amount = abs(value).formatted(.currency(code: "USD"))
        switch self {
        case .up: return L10n.string("Up %@", amount)
        case .down: return L10n.string("Down %@", amount)
        case .flat: return L10n.string("Unchanged")
        }
    }
}
