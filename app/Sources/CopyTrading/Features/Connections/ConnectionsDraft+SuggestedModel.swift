import DesktopCore

extension ConnectionsDraft {
    /// Picks a model service. A key belongs to the service it was typed for, so picking another
    /// one empties the key field: one service's key is never shown in, or sent to, another's.
    @MainActor
    mutating func pick(_ service: TradingProviderName) {
        let previous = provider
        guard service != previous else { return }
        provider = service
        providerAPIKey = ""
        suggestModel(after: previous)
    }

    /// After the owner picks a provider, the Model field shows its recommended model, unless they
    /// typed a name of their own. Only a pick changes it: opening the editor leaves the draft alone.
    @MainActor
    mutating func suggestModel(after previous: TradingProviderName) {
        let current = modelName.trimmed
        guard current.isEmpty || current == SetupHelp.prefilledModel(for: previous) else { return }
        modelName = SetupHelp.prefilledModel(for: provider) ?? ""
    }
}
