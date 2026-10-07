import SwiftUI

/// The setup tour inside a Connections panel: a quiet strip under the field it points at, in the
/// panel's own flow, so it never covers the panel's buttons or a check's result.
struct SetupTourInlineHint: View {
    let stop: SetupTourStop
    @Bindable var model: AppModel
    @State private var showsHelp = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Palette.accent)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(
                        L10n.string("Tour stop %lld of %lld", Int64(stop.rawValue + 1), Int64(SetupTourStop.allCases.count))
                            .uppercased()
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Palette.accent)
                    .monospacedDigit()
                    Text(L10n.string(stop.title))
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.ink)
                }
                Text(markdown(L10n.string(stop.detail)))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(L10n.string("Help")) { showsHelp = true }
                        .popover(isPresented: $showsHelp, arrowEdge: .bottom) { help }
                        .accessibilityIdentifier("tour.help")
                    Button(L10n.string("End Tour"), action: model.endSetupTour)
                        .accessibilityIdentifier("tour.end")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.accent)
                .padding(.top, 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
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
