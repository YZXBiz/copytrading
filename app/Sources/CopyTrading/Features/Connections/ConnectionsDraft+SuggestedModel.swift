import DesktopCore

extension ConnectionsDraft {
    /// After the owner picks a provider, the Model field shows its recommended model, unless they
    /// typed a name of their own. Only a pick changes it: opening the editor leaves the draft alone.
    @MainActor
    mutating func suggestModel(after previous: TradingProviderName) {
        let current = modelName.trimmed
        guard current.isEmpty || current == SetupHelp.prefilledModel(for: previous) else { return }
        modelName = SetupHelp.prefilledModel(for: provider) ?? ""
    }
}
