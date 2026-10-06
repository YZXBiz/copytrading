import SwiftUI

/// What CopyTrading does with each kind of post, and what it never does, so an owner knows before
/// copying when it buys, when it sells, and when it waits for them.
struct GuideCapabilitiesSection: View {
    /// What a post must say for CopyTrading to act on it, and what happens when it doesn't (ADR-0007).
    private static let needs = [
        "**The stock**: a ticker, or a name the guru's playbook maps to one. Without it, nothing is traded.",
        "**The price**: what they traded at. Without one, or \"at market\", the call waits for you.",
        "**The size**, optional: \"1/6\", \"half\", \"the first batch\". Without one, it buys your default share: the full position, unless you lower it.",
        "**For a sell, which buy**, optional: \"half of my 39.5\". For a guru whose sells refer to the buy price, a sell that doesn't say waits for you.",
    ]

    private static let never = [
        "sell shares you bought yourself",
        "short a stock, or trade options or crypto",
        "set its own stop-loss or take-profit: it sells when the guru sells, or when you do",
        "trade outside the hours you allow, or in an account whose entries are off",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GuideCapabilityRow(
                kind: "The guru buys", example: "Added 1/6 position SOUN at 5.85",
                does:
                    "**Buys** a sixth of the guru's full position (your **maximum per stock**), paying no more than their price plus your allowance. Your other limits can make it smaller or skip it."
            )
            Divider()
            GuideCapabilityRow(
                kind: "The guru sells", example: "Sold half of my 39.5 IREN at 41.27",
                does:
                    "**Sells** that part of the shares it bought on this guru's calls, at no less than their price minus 1%. Shares you bought yourself are never sold."
            )
            Divider()
            GuideCapabilityRow(
                kind: "An idea, a condition, a range", example: "If SCO dips under 20 tomorrow, I'll buy the first batch",
                does: "**Waits for you** in Activity. Copy it or skip it, until its trading day ends."
            )
            Divider()
            GuideCapabilityRow(
                kind: "Talk", example: "TSLA 373 is still resistance today",
                does: "**Nothing.** It's shown in Activity as ignored."
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("What it looks for in a post:"))
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                ForEach(Self.needs, id: \.self) { item in
                    Label {
                        Text(localizedMarkdown(item))
                            .font(DesignTokens.documentBody)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "text.magnifyingglass")
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.top, 18)
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
