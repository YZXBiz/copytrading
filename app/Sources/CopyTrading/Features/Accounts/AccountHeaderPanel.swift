import DesktopCore
import SwiftUI

/// The account's name, whether it is taking entries, and the controls that change that.
struct AccountHeaderPanel: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    private var isPending: Bool { feature.pendingAccounts.contains(account.accountID) }

    private var canControl: Bool {
        account.activeConfiguration
            && account.readiness != "account_unavailable"
            && account.readiness != "processing_stopped"
            && !isPending
    }

    /// "disabled" is how every new account starts; "paused" is an owner pause. Both block entries.
    /// After a restart with manual recovery, entries stay off until the owner resumes them, even
    /// though the saved permission still says enabled.
    private var entriesOff: Bool {
        account.entryPermission != "enabled" || account.readiness == "manual_resume_required"
    }
    private var neverEnabled: Bool { account.entryPermission == "disabled" }
    private var entryState: AccountEntryState { AccountEntryState(account) }

    var body: some View {
        PageSection {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    identity
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 16)
                    controls
                }
                VStack(alignment: .leading, spacing: 14) {
                    identity
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { controls }
                        VStack(alignment: .leading, spacing: 10) { controls }
                    }
                }
            }
            if let error = feature.errors[account.accountID] {
                Callout(error, tone: .critical)
                    .accessibilityLabel(L10n.string("Account command error: %@", error))
            }
            if neverEnabled && account.activeConfiguration {
                Label {
                    Text(
                        L10n.string(
                            "New accounts start with entries off, so nothing is bought until you turn them on. Exits are still copied.")
                    )
                    .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.yellow)
                }
                .font(.callout)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    account.environment == .live ? Color.orange.gradient : Palette.accent.gradient,
                    in: .rect(cornerRadius: 8)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(account.accountID)
                    .font(DesignTokens.pageTitle)
                HStack(spacing: 6) {
                    EnvironmentBadge(environment: account.environment)
                    Pill(text: entryState.text, symbol: entryState.tone.symbol, tint: entryState.tone.color)
                    if let pendingNote {
                        Pill(text: pendingNote, symbol: "pencil.circle.fill", tint: .orange)
                    }
                    Text(L10n.string("Alpaca"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(L10n.string("Broker account %@", account.brokerIdentity))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// An account the unsaved setup removes or changes says so beside its state.
    @MainActor private var pendingNote: String? {
        guard model.hasUnsavedSetupChanges else { return nil }
        guard let draft = model.setupDraft.accounts.first(where: { $0.name.trimmed == account.accountID }) else {
            return L10n.string("Removed — not saved yet")
        }
        let saved = model.savedTradingConfiguration?.accounts.first { $0.id == account.accountID }
        let edited = saved.map { $0.environment != draft.environment || $0.policy != draft.policy } ?? false
        return edited || !draft.key.isEmpty || !draft.secret.isEmpty ? L10n.string("Changed — not saved yet") : nil
    }

    private var isInSetup: Bool {
        model.setupDraft.accounts.contains { $0.name.trimmed == account.accountID }
    }

    @ViewBuilder
    private var controls: some View {
        if isPending {
            ProgressView()
                .controlSize(.small)
                .help(L10n.string("Saving account command"))
        }
        Menu {
            Picker(L10n.string("Recovery"), selection: recovery) {
                ForEach(RecoveryPreference.allCases, id: \.self) { preference in
                    Text(recoveryTitle(preference)).tag(preference)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(L10n.string("Recovery: %@", recoveryTitle(account.recoveryPreference)), systemImage: "arrow.triangle.2.circlepath")
        }
        .fixedSize()
        .disabled(!canControl)
        .help(L10n.string("Automatic recovery resumes entries after a restart once the account checks out; manual waits for you."))
        if entriesOff {
            Button(L10n.string(neverEnabled ? "Enable Entries" : "Resume Entries"), systemImage: "play.fill", action: toggleEntries)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.regular)
                .disabled(!canControl)
                .help(L10n.string("Allow new entry orders for this account."))
        } else {
            Button(L10n.string("Pause Entries"), systemImage: "pause.fill", action: toggleEntries)
                .controlSize(.regular)
                .disabled(!canControl)
                .help(L10n.string("Stop new entry orders. Exits still follow the account policy."))
        }
        Button(L10n.string("Edit in Connections"), systemImage: "slider.horizontal.3", action: edit)
            .labelStyle(.iconOnly)
            .disabled(!isInSetup)
            .help(L10n.string("Edit this account's keys and limits in Connections"))
    }

    private func edit() {
        model.selectedScreen = .connections
        model.editAccount(named: account.accountID)
    }

    /// Turning entries on in a live account lets it buy with real money on its own, so it asks for
    /// Touch ID first. Pausing never asks.
    private func toggleEntries() {
        let action: AccountControlAction = entriesOff ? .resume : .pause
        Task {
            if action == .resume, account.environment == .live {
                do {
                    try await model.confirmOwner(L10n.string("allow new entries in %@", account.accountID))
                } catch {
                    return
                }
            }
            await feature.control(accountID: account.accountID, action: action, using: model.accountActions())
        }
    }

    /// The engine owns the preference: a pick sends the command and the row redraws from its answer.
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

    @MainActor private func recoveryTitle(_ preference: RecoveryPreference) -> String {
        switch preference {
        case .manual: L10n.string("Manual")
        case .automatic: L10n.string("Automatic")
        }
    }
}
