import SwiftUI

/// The foot of Connections while there is something to start, set apart by space: how far the
/// setup has come, and the one Start Copying that checks every connection and starts. Results stay
/// a click away.
struct ConnectionsStartCard: View {
    @Bindable var model: AppModel
    @State private var confirmDiscard = false

    private var progress: SetupProgress { model.setupProgress }

    private var status: SetupChangesStatus { SetupChangesStatus(model) }

    private var hasResults: Bool {
        model.tradingValidation != nil || !model.profileExampleReviews.isEmpty
    }

    private var canDiscard: Bool {
        model.savedTradingConfiguration != nil && model.hasUnsavedSetupChanges
            && !model.isValidatingTrading && !model.isActivatingTrading
    }

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(DesignTokens.cardTitle)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("setup.status")
                if let detail {
                    Text(detail)
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.isValidatingTrading {
                Button(L10n.string("Cancel Check"), role: .cancel, action: cancelCheck)
            } else if !status.isWorking {
                if canDiscard {
                    Button(L10n.string("Discard Changes"), role: .destructive, action: askToDiscard)
                        .confirmationDialog(L10n.string("Discard your setup changes?"), isPresented: $confirmDiscard) {
                            Button(L10n.string("Discard Changes"), role: .destructive, action: model.discardSetupChanges)
                            Button(L10n.string("Keep Editing"), role: .cancel) {}
                        } message: {
                            Text(
                                L10n.string(
                                    "Edits and typed keys since your last saved setup are dropped. Your saved setup stays as it is."))
                        }
                }
                if hasResults {
                    Button(L10n.string("Review…"), systemImage: "checklist", action: review)
                        .accessibilityIdentifier("setup.review")
                }
            }
            if !status.isWorking {
                StartCopyingButton(model: model)
                    .setupTourTarget(.startCopying)
            }
        }
        .buttonStyle(PageButtonStyle())
        .padding(.vertical, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Start copying"))
    }

    @ViewBuilder
    private var icon: some View {
        if !progress.isReadyToCheck {
            Image(systemName: "hourglass")
                .font(.system(size: 18))
                .foregroundStyle(Palette.tertiaryInk)
        } else if status.isWorking {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: status.symbol)
                .font(.system(size: 20))
                .foregroundStyle(status.tone.color)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var headline: String {
        // The same count as the guide and Settings: the fifth step is this card's Start Copying.
        progress.isReadyToCheck
            ? status.text : L10n.string("%lld of %lld steps done", Int64(progress.completed), Int64(progress.total))
    }

    private var detail: String? {
        if let next = progress.next, !progress.isReadyToCheck {
            return L10n.string("Next: %@.", L10n.string(next.title))
        }
        if let detail = status.detail {
            return detail
        }
        if model.savedTradingConfiguration == nil && !status.isWorking {
            return L10n.string("Live accounts ask for Touch ID before copying starts.")
        }
        return nil
    }

    private func cancelCheck() {
        model.cancelTradingActivation(message: L10n.string("Check cancelled. Nothing was saved."))
    }

    private func askToDiscard() {
        confirmDiscard = true
    }

    private func review() {
        model.isShowingSetupCheck = true
    }
}
