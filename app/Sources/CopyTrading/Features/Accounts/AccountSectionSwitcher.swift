import SwiftUI

/// The account page's sections as a row of tracked capitals, like a studio site's navigation. The
/// chosen one is in ink with a short drawn line under it that slides across when the choice changes.
struct AccountSectionSwitcher: View {
    @Binding var selection: AccountSection
    /// A count beside a title, such as how many stocks the account holds.
    let counts: [AccountSection: Int]
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 32) {
            ForEach(AccountSection.allCases) { section in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selection = section }
                } label: {
                    label(section)
                }
                .buttonStyle(QuietPressButtonStyle())
                .accessibilityAddTraits(section == selection ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("account.section.\(section.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func label(_ section: AccountSection) -> some View {
        let isSelected = section == selection
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.string(section.title).uppercased())
                    .font(DesignTokens.eyebrow)
                    .tracking(DesignTokens.eyebrowTracking)
                if let count = counts[section], count > 0 {
                    Text(count.formatted())
                        .font(DesignTokens.eyebrow)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Palette.ink)
                        .frame(height: InkStroke.width)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .frame(height: InkStroke.width)
        }
        .fixedSize()
        .contentShape(.rect)
    }
}
