import DesktopCore
import SwiftUI

/// The gurus step: each guru in the setup with where their calls go, then a way to add another.
struct GuruRows: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsSection {
            ForEach(model.setupDraft.routes) { route in
                let status = ConnectionStatus.guru(route, in: model)
                ConnectionServiceRow(
                    brand: nil,
                    monogram: name(of: route),
                    title: name(of: route),
                    detail: status.tone == .caution ? status.text : L10n.string("%@ · %@", copies(route), status.text),
                    tone: status.tone,
                    action: L10n.string("Edit"),
                    identifier: "connections.guru"
                ) { model.setupEditor = .route(route.id) }
            }
            ConnectionServiceRow(
                brand: nil,
                symbol: "plus",
                title: L10n.string(model.setupDraft.routes.isEmpty ? "Add a guru" : "Add another guru"),
                detail: model.setupDraft.routes.isEmpty
                    ? L10n.string("Their channel, how to read their calls, and the account that copies them.") : nil,
                action: model.setupDraft.routes.isEmpty ? L10n.string("Add") : nil,
                identifier: "connections.gurus.add"
            ) { model.addGuru() }
        }
    }

    private func name(of route: TradingRouteDraft) -> String {
        route.displayName.trimmed.isEmpty ? L10n.string("Unnamed guru") : route.displayName.trimmed
    }

    /// Where the guru's calls go and the full position they are sized from:
    /// "Copies into primary · full position $600".
    private func copies(_ route: TradingRouteDraft) -> String {
        guard let connection = route.connection, !connection.accountID.trimmed.isEmpty else {
            return L10n.string("Needs an account to copy into")
        }
        let full = model.setupDraft.fullPosition(for: connection)
        guard Decimal(string: full).map({ $0 > 0 }) == true else {
            return L10n.string("Copies into %@", connection.accountID.trimmed)
        }
        return L10n.string("Copies into %@ · full position %@", connection.accountID.trimmed, dollars(full))
    }

    /// Whole dollars without cents, as a person would say an amount: "$100".
    private func dollars(_ value: String) -> String {
        guard let decimal = Decimal(string: value) else { return Humanize.usd(value) }
        return decimal.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
