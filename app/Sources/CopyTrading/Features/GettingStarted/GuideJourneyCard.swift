import SwiftUI

/// The chosen stop of a post's journey as a note under a hairline: where it is on the path, its
/// headline, one line on what happens, where to change it, and the one caution.
struct GuideJourneyCard: View {
    let index: Int
    let open: (AppModel.Screen?) -> Void
    let select: (Int) -> Void

    private var stop: GuideJourneyStop { GuideJourneyStop.all[index] }
    private var count: Int { GuideJourneyStop.all.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
                .padding(.bottom, 18)
            HStack(alignment: .center) {
                Eyebrow(L10n.string("Step %lld of %lld", Int64(index + 1), Int64(count)))
                Spacer()
                stepper
            }
            Text(L10n.string(stop.headline))
                .font(DesignTokens.cardTitle)
                .tracking(DesignTokens.listHeadingTracking)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 2)
            Text(L10n.string(stop.gist))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 16)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    caution
                    Spacer(minLength: 0)
                    setting
                }
                VStack(alignment: .leading, spacing: 8) {
                    caution
                    setting
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guide.journey.card")
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            round("chevron.left", label: "Previous step", to: index - 1)
            round("chevron.right", label: "Next step", to: index + 1)
        }
    }

    private func round(_ symbol: String, label: String, to target: Int) -> some View {
        Button {
            select(target)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Palette.well, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(QuietPressButtonStyle())
        .foregroundStyle(Palette.ink)
        .disabled(!(0..<count).contains(target))
        .opacity((0..<count).contains(target) ? 1 : 0.35)
        .help(L10n.string(label))
        .accessibilityLabel(L10n.string(label))
    }

    private var caution: some View {
        Label(L10n.string(stop.caution), systemImage: "exclamationmark.circle")
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.secondaryInk)
            .labelStyle(GuideCautionLabelStyle())
            .fixedSize()
    }

    /// Where this stop is changed, as one quiet button that goes there.
    private var setting: some View {
        Button {
            open(stop.screen)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.string(stop.setting))
                    .foregroundStyle(Palette.secondaryInk)
                Text(L10n.string(stop.placeTitle))
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .underline(color: Palette.hairline)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .font(DesignTokens.caption)
            .fixedSize()
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .help(L10n.string(stop.placeTitle))
        .accessibilityLabel("\(L10n.string(stop.setting)), \(L10n.string(stop.placeTitle))")
        .accessibilityIdentifier("guide.journey.open")
    }
}
