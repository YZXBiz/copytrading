import DesktopCore

extension TradingInstructionAction {
    /// What an example expects the reader to do, in the app's language: Buy, Reduce, or Close.
    @MainActor var title: String {
        switch self {
        case .buy: L10n.string("Buy")
        case .reduce: L10n.string("Reduce a position")
        case .close: L10n.string("Close a position")
        }
    }
}
