import SwiftUI

struct PlatformRootView: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel

    var body: some View {
        Group {
            if model.isTradingUnlocked {
                MainSplitView(model: model, accountFeature: accountFeature)
            } else {
                LockedView(model: model)
            }
        }
        .background {
            WindowSessionMonitor(
                onOpen: { model.windowDidOpen($0) },
                onClose: { model.windowDidClose($0) }
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: model.isTradingUnlocked, initial: true) { _, unlocked in
            if unlocked {
                accountFeature.authorizePrivateEvidence()
            } else {
                accountFeature.clearPrivateEvidence()
            }
        }
    }
}
