import SwiftUI

/// The tour's card: which stop of how many, a title with a quieter second line, one
/// instruction, what moves it on, and the stop's help a click away.
struct SetupTourCard: View {
    let stop: SetupTourStop
    /// The edge the caret sits on, and where along it.
    let caretEdge: Edge
    let caretOffset: CGFloat
    @Bindable var model: AppModel
    @State private var showsHelp = false

    static let width: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                L10n.string("Tour stop %lld of %lld", Int64(stop.rawValue + 1), Int64(SetupTourStop.allCases.count)).uppercased()
            )
            .font(DesignTokens.eyebrow)
            .tracking(DesignTokens.eyebrowTracking)
            .foregroundStyle(Palette.tertiaryInk)
            .monospacedDigit()
            .padding(.bottom, 8)
            // A card's title sits below a page's: the stop in the display face, its point as a lede.
            Text(L10n.string(stop.title))
                .font(DisplayFont.font(size: 19, weight: .medium, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.string(stop.subtitle))
                .font(DesignTokens.lede)
                .tracking(DesignTokens.ledeTracking)
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.top, 2)
                .padding(.bottom, 12)
            if stop == .discordRow && model.setupProgress.completed == 0 {
                Text(L10n.string("Welcome. Five steps, about 10 minutes; nothing is saved or traded until the last one."))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            Text(markdown(L10n.string(stop.detail)))
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                ZStack {
                    Circle().strokeBorder(Palette.ink, lineWidth: 1.2).frame(width: 12, height: 12)
                    Circle().fill(Palette.ink).frame(width: 5, height: 5)
                }
                .accessibilityHidden(true)
                Text(L10n.string(stop.waiting))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.top, 12)
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)
                .padding(.vertical, 12)
            HStack(spacing: 4) {
                ForEach(SetupTourStop.allCases) { other in
                    Capsule()
                        .fill(other.rawValue <= stop.rawValue ? Palette.ink : Palette.ink.opacity(0.12))
                        .opacity(other.rawValue < stop.rawValue ? 0.4 : 1)
                        .frame(width: other == stop ? 16 : 5, height: 5)
                }
                .accessibilityHidden(true)
                Spacer(minLength: 8)
                Button(L10n.string("Help")) { showsHelp = true }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.trailing, 10)
                    .popover(isPresented: $showsHelp, arrowEdge: .bottom) { help }
                    .accessibilityIdentifier("tour.help")
                Button(L10n.string("End Tour"), action: model.endSetupTour)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityIdentifier("tour.end")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: Self.width, alignment: .leading)
        .background(SetupTourBubble(edge: caretEdge, offset: caretOffset).fill(Palette.page))
        .overlay(SetupTourBubble(edge: caretEdge, offset: caretOffset).stroke(Palette.ink.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.14), radius: 28, y: 14)
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
