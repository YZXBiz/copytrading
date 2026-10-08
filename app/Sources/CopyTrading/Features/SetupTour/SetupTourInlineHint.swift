import SwiftUI

/// The setup tour inside a Connections panel: words under the field it points at, in the panel's
/// own flow, so it never covers the panel's buttons or a check's result.
struct SetupTourInlineHint: View {
    let stop: SetupTourStop
    @Bindable var model: AppModel
    @State private var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("Tour stop %lld of %lld", Int64(stop.rawValue + 1), Int64(SetupTourStop.allCases.count)))
                .font(DesignTokens.eyebrow)
                .tracking(DesignTokens.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.tertiaryInk)
                .monospacedDigit()
            Text(L10n.string(stop.title))
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(markdown(L10n.string(stop.detail)))
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button(L10n.string("Help")) { showsHelp = true }
                    .popover(isPresented: $showsHelp, arrowEdge: .bottom) { help }
                    .accessibilityIdentifier("tour.help")
                Button(L10n.string("End Tour"), action: model.endSetupTour)
                    .accessibilityIdentifier("tour.end")
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(stop)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.card")
    }

    private var help: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(SetupHelp.articles(for: stop.step, provider: model.setupDraft.provider)) { article in
                    HelpArticleView(article: article)
                }
            }
            .padding(20)
        }
        .frame(width: 380)
        .frame(maxHeight: 460)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
