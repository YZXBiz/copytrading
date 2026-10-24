import DesktopCore
import SwiftUI

/// The account's name, its mode, whether CopyTrading copies into it, its one Start or Stop
/// Copying, and its other controls tucked behind ⋯.
struct AccountPageHeader: View {
    let account: AccountOverview
    let model: AppModel
    let feature: AccountFeatureModel

    private var isPending: Bool { feature.pendingAccounts.contains(account.accountID) }
    private var copyState: CopyingState { CopyingState.account(account, processing: model.tradingStatus) }
    private var isInSetup: Bool {
        model.setupDraft.accounts.contains { $0.name.trimmed == account.accountID }
    }
    private var isSaved: Bool {
        model.savedTradingConfiguration?.accounts.contains { $0.id == account.accountID } == true
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
                    .accessibilityLabel(L10n.string("%@: %@", account.accountID, error))
            }
            if let pendingNote {
                // An edit is only in the setup until it is applied; say so where it shows.
                HStack(spacing: 12) {
                    Label(pendingNote, systemImage: "pencil.circle")
                        .foregroundStyle(Palette.secondaryInk)
                    Button(L10n.string("Review in Connections"), action: openConnections)
                        .buttonStyle(QuietTextButtonStyle())
                }
                .font(DesignTokens.caption)
            } else if model.limitsSavedAccountIDs.contains(account.accountID) {
                Label(L10n.string("Saved · applies to the next order"), systemImage: StatusTone.positive.symbol)
                    .foregroundStyle(StatusTone.positive.color)
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

    /// The name, large and plain, with its mode and whether it copies in one grey line under it. Only a
    /// live account's mode carries colour, since it trades real money.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(account.accountID)
                .font(DesignTokens.entityTitle)
                .tracking(DesignTokens.entityTitleTracking)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
                .help(L10n.string("Broker account %@", account.brokerIdentity))
            HStack(spacing: 10) {
                // The mode as a small tag; only a live account's carries colour, since it trades real money.
                Text(L10n.string(account.environment == .live ? "Live" : "Paper"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(account.environment == .live ? Palette.live : Palette.secondaryInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        account.environment == .live ? Palette.live.opacity(0.12) : Palette.group, in: .rect(cornerRadius: 5))
                HStack(spacing: 7) {
                    Circle()
                        .fill(copyState.isCopying ? Palette.gain : Palette.tertiaryInk.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(copyState.text)
                        .foregroundStyle(
                            copyState.tone == .caution || copyState.tone == .critical ? Palette.amber : Palette.tertiaryInk)
                }
            }
            .font(DesignTokens.caption.weight(.medium))
            .accessibilityElement(children: .combine)
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
            if copyState.isCopying {
                Button(L10n.string("Stop Copying"), systemImage: "stop.fill", action: stop)
                    .buttonStyle(PageButtonStyle())
                    .disabled(isPending || model.isTradingCommandPending)
                    .help(L10n.string("No new buys in this account. Sells of what it copied still follow the guru."))
                    .labelStyle(.titleOnly)
                    .accessibilityIdentifier("account.copying")
            } else {
                Button(
                    L10n.string(account.environment == .live ? "Start Copying…" : "Start Copying"), systemImage: "play.fill",
                    action: start
                )
                .buttonStyle(PageButtonStyle(emphasis: .prominent))
                .disabled(!isSaved || isPending || model.isTradingCommandPending || !model.isTradingUnlocked)
                .help(
                    L10n.string(
                        isSaved
                            ? "Copy the guru's buys and sells into this account."
                            : "Save this account in Connections before copying into it.")
                )
                .labelStyle(.titleOnly)
                .accessibilityIdentifier("account.copying")
            }
            AccountPageMenu(account: account, isInSetup: isInSetup, model: model)
        }
    }

    private func start() {
        Task { await model.startCopying(into: account.accountID, environment: account.environment, feature: feature) }
    }

    private func stop() {
        Task { await model.stopCopying(into: account.accountID, feature: feature) }
    }

    private func openConnections() {
        model.selectedScreen = .connections
        model.editAccount(named: account.accountID)
    }
}
