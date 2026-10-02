import SwiftUI

/// Unsaved setup changes, wherever they were made, in one floating glass bar: check them, then
/// start copying. Edits spread across Connections, People, and Accounts, but saving stays a
/// single, checked step.
struct SetupChangesBar: View {
    @Bindable var model: AppModel
    @State private var confirmDiscard = false

    private var status: SetupChangesStatus { SetupChangesStatus(model) }

    private var hasResults: Bool {
        model.tradingValidation != nil || !model.profileExampleReviews.isEmpty
    }

    private var canDiscard: Bool {
        model.savedTradingConfiguration != nil && model.hasUnsavedSetupChanges
            && !model.isValidatingTrading && !model.isActivatingTrading
    }

    private var canCheck: Bool {
        model.tradingStatus?.state == .paused && !model.isValidatingTrading && !model.isActivatingTrading
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if status.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.tone.color)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)
            Text(status.text)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .accessibilityIdentifier("setup.status")
            Spacer(minLength: 12)
            if model.isValidatingTrading {
                Button(L10n.string("Cancel Check"), role: .cancel, action: cancelCheck)
            } else {
                if canDiscard {
                    Button(L10n.string("Discard Changes"), role: .destructive, action: askToDiscard)
                        .confirmationDialog(L10n.string("Discard your setup changes?"), isPresented: $confirmDiscard) {
                            Button(L10n.string("Discard Changes"), role: .destructive, action: discard)
                            Button(L10n.string("Keep Editing"), role: .cancel) {}
                        } message: {
                            Text(
                                L10n.string(
                                    "Edits and typed keys since your last saved setup are dropped. Your saved setup stays as it is."))
                        }
                }
                if hasResults {
                    Button(L10n.string("Review…"), systemImage: "checklist", action: review)
                }
            }
            Button(L10n.string("Check Setup"), systemImage: "checkmark.shield", action: model.checkSetup)
                .disabled(!canCheck)
                .accessibilityIdentifier("setup.check")
            StartCopyingButton(model: model)
        }
        .controlSize(.large)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 820)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Unsaved setup"))
    }

    private func cancelCheck() {
        model.cancelTradingActivation(message: L10n.string("Check cancelled. Nothing was saved."))
    }

    private func askToDiscard() {
        confirmDiscard = true
    }

    private func discard() {
        model.discardSetupChanges()
    }

    private func review() {
        model.isShowingSetupCheck = true
    }
}
