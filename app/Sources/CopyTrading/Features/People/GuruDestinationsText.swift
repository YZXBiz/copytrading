import DesktopCore
import SwiftUI

/// Where a guru's calls go, from the saved routes, as the quiet line under their name:
/// "Copies into primary (Paper) and ira (Live)". Only Live carries colour, since it is real money.
@MainActor
enum GuruDestinationsText {
    static func text(_ guru: GuruDirectory.Guru?, in configuration: TradingConfiguration?) -> AttributedString? {
        guard let guru, !guru.destinations.isEmpty else { return nil }
        var seen: Set<String> = []
        let accounts = guru.destinations.map(\.accountID).filter { seen.insert($0).inserted }.map { accountID in
            (accountID, configuration?.accounts.first { $0.id == accountID }?.environment)
        }
        let names = accounts.map { accountID, environment in
            environment.map { L10n.string("%@ (%@)", accountID, mode($0)) } ?? accountID
        }
        var text = AttributedString(
            L10n.string("Copies into %@", names.formatted(.list(type: .and).locale(AppTime.locale))))
        for (accountID, environment) in accounts where environment == .live {
            let name = L10n.string("%@ (%@)", accountID, mode(.live))
            guard let range = text.range(of: name) else { continue }
            let live = text[range].range(of: mode(.live), options: .backwards) ?? range
            text[live].foregroundColor = .orange
        }
        return text
    }

    private static func mode(_ environment: TradingEnvironment) -> String {
        L10n.string(environment == .live ? "Live" : "Paper")
    }
}
