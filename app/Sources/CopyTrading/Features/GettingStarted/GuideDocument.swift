import SwiftUI

/// The guide's white page: title, lead, the opening figure, the checklist, how a post becomes a
/// trade, what to know before copying,
/// shortcuts, and where to get help.
struct GuideDocument: View {
    @Bindable var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            GuideHeader(progress: model.setupProgress)
                .id(GuideAnchor.top)
            GuideLeadBlock()
            GuideFlowFigure()
            GuideSection("Get set up") {
                SetupChecklist(model: model)
            }
            .id(GuideAnchor.setUp)
            GuideSection("How a post becomes a trade") {
                GuideJourneySection()
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
