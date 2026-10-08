import SwiftUI

/// The guide's white page: title with the setup tour's button, how a
/// post becomes a trade, what to know before copying, shortcuts, and where to get help.
struct GuideDocument: View {
    @Bindable var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            GuideHeader(progress: model.setupProgress, startTour: model.startSetupTour)
                .id(GuideAnchor.top)
            GuideSection("How a post becomes a trade") {
                GuideJourneySection(open: { model.selectedScreen = $0 })
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
        .padding(.vertical, 40)
        .frame(maxWidth: DesignTokens.readingContentMaxWidth, alignment: .leading)
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.readingCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.readingCornerRadius)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
    }
}
