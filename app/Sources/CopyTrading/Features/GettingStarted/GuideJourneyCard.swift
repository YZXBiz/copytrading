import SwiftUI

/// The chosen stop of a post's journey as a tinted page in a white frame: where it is on the
/// path, its serif headline, one line on what happens, where to change it, and the one caution.
struct GuideJourneyCard: View {
    let index: Int
    let open: (AppModel.Screen) -> Void
    let select: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var stop: GuideJourneyStop { GuideJourneyStop.all[index] }
    private var count: Int { GuideJourneyStop.all.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Step %lld of %lld", Int64(index + 1), Int64(count)))
                    .font(DesignTokens.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
                Spacer()
                stepper
            }
            Text(L10n.string(stop.headline))
                .font(DesignTokens.cardSerif)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 2)
            Text(L10n.string(stop.gist))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Divider()
                .overlay(Palette.ink.opacity(0.04))
                .padding(.vertical, 14)
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
        .padding(22)
        .background(tint, in: .rect(cornerRadius: 15))
        .padding(6)
        .background(Palette.page, in: .rect(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(
                    contrast == .increased ? Palette.secondaryInk : Palette.ink.opacity(0.06), lineWidth: contrast == .increased ? 1 : 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
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
                .frame(width: 26, height: 26)
                .background(Palette.page.opacity(0.8), in: .circle)
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5))
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
                Text(L10n.string(stop.screen.title))
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.accent)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            .font(DesignTokens.caption)
            .fixedSize()
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .help(L10n.string(stop.screen.title))
        .accessibilityLabel("\(L10n.string(stop.setting)), \(L10n.string(stop.screen.title))")
        .accessibilityIdentifier("guide.journey.open")
    }

    /// Soft tints in the idea cards' family, turning from sky to lilac along the path.
    private var tint: Color {
        let dark = colorScheme == .dark
        let sky = dark ? Color(red: 0.14, green: 0.18, blue: 0.22) : Color(red: 0.941, green: 0.969, blue: 0.996)
        let lilac = dark ? Color(red: 0.18, green: 0.17, blue: 0.22) : Color(red: 0.961, green: 0.949, blue: 0.996)
        return sky.mix(with: lilac, by: Double(index) / Double(count - 1))
    }
}
