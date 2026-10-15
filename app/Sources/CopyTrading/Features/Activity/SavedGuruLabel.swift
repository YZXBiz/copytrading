import DesktopCore

/// A saved guru as a choice reads: their name and the accounts they copy into, never the channel or
/// author numbers that route their posts.
enum SavedGuruLabel {
    @MainActor static func text(_ route: TradingRouteConfiguration, in configuration: TradingConfiguration?) -> String {
        let name =
            configuration?.profiles.first(where: { $0.profileRevision == route.profileRevision })?.displayName
            ?? route.guruID
        let accounts = route.connections.map(\.accountID).joined(separator: ", ")
        return accounts.isEmpty ? name : L10n.string("%@ · %@", name, accounts)
    }
}
