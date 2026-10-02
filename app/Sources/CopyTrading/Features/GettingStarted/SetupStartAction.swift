import SwiftUI

/// The last step, done in place: check the setup, then start copying, with the same words the
/// changes bar uses.
struct SetupStartAction: View {
    @Bindable var model: AppModel

    private var isRunningSetup: Bool {
        model.savedTradingConfiguration != nil && !model.hasUnsavedSetupChanges
    }

    private var canCheck: Bool {
        model.setupProgress.isReadyToCheck && model.tradingStatus?.state == .paused
            && !model.isValidatingTrading && !model.isActivatingTrading
    }

    var body: some View {
        if isRunningSetup {
            Label(
                L10n.string("Your setup is saved. Change anything from Connections, People, or Accounts."),
                systemImage: "checkmark.seal.fill"
            )
            .font(DesignTokens.bodyText)
            .foregroundStyle(Palette.secondaryInk)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button(L10n.string("Check Setup"), systemImage: "checkmark.shield", action: model.checkSetup)
                        .modifier(GuideActionStyle(isPrimary: !model.canStartCopyingFromCheck))
                        .disabled(!canCheck)
                        .accessibilityIdentifier("guide.checkSetup")
                    StartCopyingButton(model: model)
                }
                Text(
                    model.setupProgress.isReadyToCheck
                        ? L10n.string(SetupChangesStatus(model).text) : L10n.string("Finish the steps above first.")
                )
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .contentTransition(.opacity)
            }
        }
    }
}
