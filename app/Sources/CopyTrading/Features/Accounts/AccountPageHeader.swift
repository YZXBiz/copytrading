import DesktopCore
import SwiftUI

/// The account's name and mode, whether it is taking entries, the switch that changes that, and
/// the rest of its controls tucked behind ⋯.
struct AccountPageHeader: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    private var isPending: Bool { feature.pendingAccounts.contains(account.accountID) }

    /// Readiness values for an account that is not running, so there is nothing to control.
    private static let notRunning: Set<String> = [
        "account_unavailable", "processing_stopped", "outside_open_orders", "broker_account_inactive",
        "account_in_use",
    ]

    private var canControl: Bool {
        account.activeConfiguration && !Self.notRunning.contains(account.readiness) && !isPending
    }

    /// "disabled" is how every new account starts; "paused" is an owner pause. Both block entries.
    /// After a restart with manual recovery, entries stay off until the owner resumes them, even
    /// though the saved permission still says enabled.
    private var entriesOff: Bool {
        account.entryPermission != "enabled" || account.readiness == "manual_resume_required"
    }
    private var neverEnabled: Bool { account.entryPermission == "disabled" }
    private var entryState: AccountEntryState { AccountEntryState(account) }
    private var isInSetup: Bool {
        model.setupDraft.accounts.contains { $0.name.trimmed == account.accountID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    identity
                    Spacer(minLength: 16)
                    controls
                }
                VStack(alignment: .leading, spacing: 12) {
                    identity
                    controls
                }
            }
            if let error = feature.errors[account.accountID] {
                Callout(error, tone: .critical)
                    .accessibilityLabel(L10n.string("Account command error: %@", error))
            }
            if let pendingNote {
                // An edit is only in the setup until it is applied; say so where it shows.
                HStack(spacing: 12) {
                    Label(pendingNote, systemImage: "pencil.circle")
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: 12)
                    StartCopyingButton(model: model)
                        .controlSize(.small)
                }
                .font(DesignTokens.caption)
            } else if model.limitsSavedAccountIDs.contains(account.accountID) {
                Label(L10n.string("Saved · applies to the next order"), systemImage: StatusTone.positive.symbol)
                    .foregroundStyle(StatusTone.positive.color)
                    .font(DesignTokens.caption)
            }
            if neverEnabled && account.activeConfiguration {
                Label {
                    Text(
                        L10n.string(
                            "New accounts start with entries off, so nothing is bought until you turn them on. Exits are still copied.")
                    )
                    .foregroundStyle(Palette.secondaryInk)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Palette.amber)
                }
                .font(DesignTokens.caption)
            }
        }
    }

    /// An account the unsaved setup removes or changes says so under its name.
    @MainActor private var pendingNote: String? {
        // Limits alone apply the moment the sheet closes; only other edits wait for Start.
        guard model.hasUnsavedSetupChanges, !model.hasOnlyLimitChanges else { return nil }
        guard let draft = model.setupDraft.accounts.first(where: { $0.name.trimmed == account.accountID }) else {
            return L10n.string("Removed — not saved yet")
        }
        let saved = model.savedTradingConfiguration?.accounts.first { $0.id == account.accountID }
        let edited = saved.map { $0.environment != draft.environment || $0.policy != draft.policy } ?? false
        return edited || !draft.key.isEmpty || !draft.secret.isEmpty ? L10n.string("Changed — not saved yet") : nil
    }

    /// The name, large and plain, with its mode and entry state in one grey line under it. Only a
    /// live account's mode carries colour, since it trades real money.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(account.accountID)
                .font(DesignTokens.entityTitle)
                .tracking(DesignTokens.entityTitleTracking)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
                .help(L10n.string("Broker account %@", account.brokerIdentity))
            HStack(spacing: 6) {
                Text(L10n.string(account.environment == .live ? "Live" : "Paper"))
                    .foregroundStyle(account.environment == .live ? Color.orange : Palette.tertiaryInk)
                Text(verbatim: "·")
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
                Text(L10n.string(entryState.text))
                    .foregroundStyle(entryState.tone == .caution ? Palette.amber : Palette.tertiaryInk)
            }
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .help(L10n.string("Saving account command"))
            }
            // Entries only mean something while the engine holds the account, so the switch waits
            // until copying runs.
            if account.activeConfiguration {
                if entriesOff {
                    Button(L10n.string(neverEnabled ? "Enable Entries" : "Resume Entries"), systemImage: "play.fill", action: toggleEntries)
                        .buttonStyle(PageButtonStyle(isProminent: true))
                        .disabled(!canControl)
                        .help(L10n.string("Allow new entry orders for this account."))
                        .labelStyle(.titleOnly)
                        .accessibilityIdentifier("account.entries")
                } else {
                    Button(L10n.string("Pause Entries"), systemImage: "pause.fill", action: toggleEntries)
                        .buttonStyle(PageButtonStyle())
                        .disabled(!canControl)
                        .help(L10n.string("Stop new entry orders. Exits still follow the account policy."))
                        .labelStyle(.titleOnly)
                        .accessibilityIdentifier("account.entries")
                }
            }
            AccountPageMenu(account: account, canControl: canControl, isInSetup: isInSetup, model: model, feature: feature)
        }
    }

    /// Turning entries on in a live account lets it buy with real money on its own, so it asks for
    /// Touch ID first. Pausing never asks.
    private func toggleEntries() {
        Task {
            if entriesOff {
                await model.resumeEntries(accountID: account.accountID, environment: account.environment, feature: feature)
            } else {
                await feature.control(accountID: account.accountID, action: .pause, using: model.accountActions())
            }
        }
    }
}
