import SwiftUI

/// What CopyTrading does with each kind of post, and what it never does, so an owner knows before
/// copying when it buys, when it sells, and when it waits for them.
struct GuideCapabilitiesSection: View {
    private static let never = [
        "sell shares you bought yourself",
        "short a stock, or trade options or crypto",
        "set its own stop-loss or take-profit: it sells when the guru sells, or when you do",
        "trade outside the hours you allow, or in an account whose entries are off",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GuideCapabilityRow(
                kind: "The guru buys", example: "5.85加了6分之一常规仓soun",
                does:
                    "**Buys** a sixth of the guru's full position (your **maximum per stock**), paying no more than their price plus your allowance. Your other limits can make it smaller or skip it."
            )
            Divider()
            GuideCapabilityRow(
                kind: "The guru sells", example: "41.27出一半39.5的iren",
                does:
                    "**Sells** that part of the shares it bought on this guru's calls, at no less than their price minus 1%. Shares you bought yourself are never sold."
            )
            Divider()
            GuideCapabilityRow(
                kind: "An idea, a condition, a range", example: "如果明天20以下我会买第一批",
                does: "**Waits for you** in Activity. Copy it or skip it, until its trading day ends."
            )
            Divider()
            GuideCapabilityRow(
                kind: "Talk", example: "Tsla 373 今天依然压力位",
                does: "**Nothing.** It's shown in Activity as ignored."
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("It never:"))
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                ForEach(Self.never, id: \.self) { item in
                    Label {
                        Text(L10n.string(item))
                            .font(DesignTokens.documentBody)
                            .foregroundStyle(Palette.ink)
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.top, 18)
        }
    }
}
