import DesktopCore
import Foundation

/// Where a guru's calls go, from the saved routes: "Copies into primary (Paper) and ira (Live)".
@MainActor
enum GuruDestinationsText {
    static func text(_ guru: GuruDirectory.Guru?, in configuration: TradingConfiguration?) -> String? {
        guard let guru, !guru.destinations.isEmpty else { return nil }
        var seen: Set<String> = []
        let accounts = guru.destinations.map(\.accountID).filter { seen.insert($0).inserted }.map { accountID in
            let environment = configuration?.accounts.first { $0.id == accountID }?.environment
            return environment.map { L10n.string("%@ (%@)", accountID, L10n.string($0 == .live ? "Live" : "Paper")) } ?? accountID
        }
        return L10n.string("Copies into %@", accounts.formatted(.list(type: .and).locale(AppTime.locale)))
    }
}
