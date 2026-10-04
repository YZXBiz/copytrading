import SwiftUI

/// The last step, done in place: Start Copying checks the setup and starts, with the same words
/// Connections uses.
struct SetupStartAction: View {
    @Bindable var model: AppModel

    private var isRunningSetup: Bool {
        model.savedTradingConfiguration != nil && !model.hasUnsavedSetupChanges
    }

    var body: some View {
        if isRunningSetup {
            Label(L10n.string("Your setup is saved. Change anything in Connections."), systemImage: "checkmark.seal.fill")
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                StartCopyingButton(model: model)
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
