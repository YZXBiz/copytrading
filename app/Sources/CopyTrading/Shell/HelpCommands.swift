import SwiftUI

/// The Help menu: the guide, its shortcut reference, the tips, and where to report a problem.
struct HelpCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(L10n.string("Getting Started"), action: openGuide)
                .disabled(!model.isTradingUnlocked)
            Button(L10n.string("Keyboard Shortcuts"), action: openShortcuts)
                .disabled(!model.isTradingUnlocked)
            Divider()
            Button(L10n.string("Show Tips Again"), action: model.showTipsAgain)
            Divider()
            Link(L10n.string("Report a Problem…"), destination: HelpLinks.reportProblem)
        }
    }

    private func openGuide() {
        model.guideAnchor = .top
        model.selectedScreen = .gettingStarted
    }

    private func openShortcuts() {
        model.guideAnchor = .shortcuts
        model.selectedScreen = .gettingStarted
    }
}
