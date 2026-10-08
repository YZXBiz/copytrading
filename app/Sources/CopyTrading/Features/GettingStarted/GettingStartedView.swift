import SwiftUI

/// The how-to, written as one white page: a hero whose steps tick themselves as the setup fills
/// in, how a post travels, the safety controls, and every shortcut.
struct GettingStartedView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GuideDocument(model: model)
                    .padding(.horizontal, DesignTokens.pagePadding)
                    .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .onChange(of: model.guideAnchor, initial: true) { _, anchor in
                reveal(anchor, using: proxy)
            }
        }
        .navigationTitle(L10n.string("Getting Started"))
    }

    /// Scrolls to the section the Help menu or Today asked for.
    private func reveal(_ anchor: GuideAnchor?, using proxy: ScrollViewProxy) {
        guard let anchor else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
        model.guideAnchor = nil
    }
}
