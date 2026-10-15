import Foundation

extension AppModel {
    static let tipGenerationKey = "tips.generation"

    /// Re-arms every tip: each one takes the new generation into its identity, so TipKit treats
    /// it as never shown. Tips wait for the screens they point at, so the owner is told when.
    func showTipsAgain() {
        tipGeneration += 1
        UserDefaults.standard.set(tipGeneration, forKey: Self.tipGenerationKey)
        message =
            savedTradingConfiguration == nil
            ? L10n.string("Tips will show again once copying is set up, each beside what it points at.")
            : L10n.string("Tips will show again, each beside what it points at.")
    }
}
