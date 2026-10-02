import SwiftUI

/// What a checklist step offers to do: open the place the step happens, or, for the last step,
/// check the setup and start copying right here.
struct SetupStepAction: View {
    let step: SetupStep
    let isDone: Bool
    @Bindable var model: AppModel

    var body: some View {
        switch step {
        case .discord:
            Button(L10n.string("Open Connections"), systemImage: "cloud", action: openDiscord)
                .modifier(GuideActionStyle(isPrimary: !isDone))
                .accessibilityIdentifier("guide.openDiscord")
        case .interpreter:
            Button(L10n.string("Open Connections"), systemImage: "cloud", action: openInterpreter)
                .modifier(GuideActionStyle(isPrimary: !isDone))
                .accessibilityIdentifier("guide.openInterpreter")
        case .account:
            Button(
                model.setupDraft.accounts.isEmpty ? L10n.string("Add Account") : L10n.string("Open Accounts"),
                systemImage: model.setupDraft.accounts.isEmpty ? "plus" : "building.columns",
                action: openAccounts
            )
            .modifier(GuideActionStyle(isPrimary: !isDone))
            .accessibilityIdentifier("guide.openAccounts")
        case .guru:
            Button(
                model.setupDraft.routes.isEmpty ? L10n.string("Add Guru") : L10n.string("Open People"),
                systemImage: model.setupDraft.routes.isEmpty ? "plus" : "person.2",
                action: openPeople
            )
            .modifier(GuideActionStyle(isPrimary: !isDone))
            .accessibilityIdentifier("guide.openPeople")
        case .start:
            SetupStartAction(model: model)
        }
    }

    private func openDiscord() {
        model.open(.discord)
    }

    private func openInterpreter() {
        model.open(.interpreter)
    }

    /// Adds the first account, or opens the first one still missing its keys.
    private func openAccounts() {
        model.selectedScreen = .accounts
        if model.setupDraft.accounts.isEmpty {
            model.addAccount()
        } else if let missing = model.setupDraft.accounts.first(where: needsKeys) {
            model.setupEditor = .account(missing.id)
        }
    }

    /// Adds the first guru, or opens the first one not ready to copy yet.
    private func openPeople() {
        model.selectedScreen = .people
        if model.setupDraft.routes.isEmpty {
            model.addGuru()
        } else if !isDone,
            let unfinished = model.setupDraft.routes.first(where: { $0.displayName.trimmed.isEmpty || $0.connections.isEmpty })
        {
            model.setupEditor = .route(unfinished.id)
        }
    }

    private func needsKeys(_ account: TradingAccountDraft) -> Bool {
        (account.key.isEmpty || account.secret.isEmpty) && !model.savedKeyAccountIDs.contains(account.name.trimmed)
    }
}
