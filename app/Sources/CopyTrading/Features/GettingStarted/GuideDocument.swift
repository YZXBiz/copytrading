import SwiftUI

/// The guide as one airy page: the hero with the setup steps, how a post becomes a
/// trade, what to know before copying, shortcuts, and where to get help. Sections are set apart
/// by space and hairlines, never boxes.
struct GuideDocument: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 64) {
            VStack(alignment: .leading, spacing: 40) {
                GuideHeader(progress: model.setupProgress, startTour: model.startSetupTour)
                GuideStepList(progress: model.setupProgress) { model.selectedScreen = .connections }
            }
            .id(GuideAnchor.top)
            GuideSection("How a post becomes a trade") {
                GuideJourneySection(
                    firstAccount: model.savedTradingConfiguration?.accounts.first?.id, open: { model.selectedScreen = $0 })
            }
            GuideSection("Before you go") {
                GuideBeforeYouGoSection()
            }
            GuideSection("Shortcuts") {
                GuideShortcutsSection()
            }
            .id(GuideAnchor.shortcuts)
            GuideFooter(model: model)
        }
        .padding(.horizontal, DesignTokens.documentInset)
        .padding(.top, 36)
        .padding(.bottom, 48)
        .frame(maxWidth: 820, alignment: .leading)
    }
}
