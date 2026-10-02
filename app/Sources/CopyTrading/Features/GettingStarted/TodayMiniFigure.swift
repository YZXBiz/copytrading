import SwiftUI

/// Today in miniature: the day's equity, its change, and the curve.
struct TodayMiniFigure: View {
    var body: some View {
        GuideFigure(
            description: L10n.string("Example of Today: equity of $25,412.18, up $212.40 today, with a rising curve."),
            showsWindowControls: false
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Equity today"))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.secondaryInk)
                MoneyText(value: Decimal(string: "25412.18") ?? 0, font: .title2.weight(.medium))
                    .foregroundStyle(Palette.ink)
                MoneyText(value: Decimal(string: "212.40") ?? 0, style: .change, font: .callout)
                GuideSparkline()
                    .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.page, in: .rect(cornerRadius: 10))
        }
    }
}
