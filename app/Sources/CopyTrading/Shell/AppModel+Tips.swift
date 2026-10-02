import Foundation

extension AppModel {
    static let tipGenerationKey = "tips.generation"

    /// Re-arms every tip: each one takes the new generation into its identity, so TipKit treats
    /// it as never shown.
    func showTipsAgain() {
        tipGeneration += 1
        UserDefaults.standard.set(tipGeneration, forKey: Self.tipGenerationKey)
    }
}
