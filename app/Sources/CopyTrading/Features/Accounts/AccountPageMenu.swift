import DesktopCore
import SwiftUI

/// The account's less frequent controls behind ⋯: its limits, its keys in Connections, and what it
/// does after a restart.
struct AccountPageMenu: View {
    let account: AccountOverview
    let canControl: Bool
    let isInSetup: Bool
    let model: AppModel
    let feature: AccountFeatureModel

    var body: some View {
        Menu(L10n.string("More for this account"), systemImage: "ellipsis") {
            Button(L10n.string("Edit Limits…"), systemImage: "slider.horizontal.3", action: editLimits)
                .disabled(!isInSetup)
            Button(L10n.string("Edit in Connections"), systemImage: "point.3.connected.trianglepath.dotted", action: editInConnections)
                .disabled(!isInSetup)
            Divider()
            Picker(L10n.string("After a restart"), selection: recovery) {
                ForEach(RecoveryPreference.allCases, id: \.self) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            .disabled(!canControl)
            .help(
                L10n.string(
                    "After CopyTrading restarts, from a crash, a Mac restart, waking from sleep, or a restore, this account either waits for you before buying again or carries on by itself once Alpaca matches its records."
                ))
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PageButtonStyle(horizontalPadding: 8))
        .fixedSize()
        .help(L10n.string("More for this account"))
        .accessibilityIdentifier("account.more")
    }

    private func editLimits() {
        model.editAccount(named: account.accountID)
    }

    private func editInConnections() {
        model.selectedScreen = .connections
        model.editAccount(named: account.accountID)
    }

    /// The engine owns the preference: a pick sends the command and the menu redraws from its answer.
    private var recovery: Binding<RecoveryPreference> {
        Binding(get: { account.recoveryPreference }, set: setRecovery)
    }

    private func setRecovery(_ preference: RecoveryPreference) {
        Task {
            await feature.control(
                accountID: account.accountID, action: .setRecovery,
                preference: preference, using: model.accountActions()
            )
        }
    }
}
