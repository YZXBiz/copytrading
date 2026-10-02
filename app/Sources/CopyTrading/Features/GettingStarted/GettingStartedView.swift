import SwiftUI

/// The how-to, written as a document: a white
/// page on the canvas with a checklist that ticks itself as the setup fills in, live pictures of
/// each screen, the safety controls, and every shortcut.
struct GettingStartedView: View {
    @Bindable var model: AppModel
    let feature: AccountFeatureModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GuideDocument(model: model)
                    .padding(.horizontal, DesignTokens.pagePadding)
                    .padding(.top, DesignTokens.pageTopPadding + 10)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
            }
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
