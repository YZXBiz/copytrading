import SwiftUI

/// The three stages of a post's trip, side by side, with sample data that reads like a real call.
struct GuideFlowStages: View {
    let litStage: Int

    var body: some View {
        GuideFlowCard(number: 1, caption: "A guru posts", isLit: litStage == 1) {
            HStack(spacing: 8) {
                GuruMonogram(name: "Alex Chen", size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Alex Chen")
                        .font(DesignTokens.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("9:41 AM")
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            Text("Bought NVDA 1/6 at 121.38")
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        GuideFlowConnector(isLit: litStage == 2)
        GuideFlowCard(number: 2, caption: "CopyTrading reads it", isLit: litStage == 2) {
            Text(L10n.string("Understood as"))
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
            Text(L10n.string("Buy %@ at %@", "NVDA", "$121.38"))
                .font(DesignTokens.bodyEmphasis)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(L10n.string("A sixth of a position, inside your limits"))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        GuideFlowConnector(isLit: litStage == 3)
        GuideFlowCard(number: 3, caption: "Your account trades", isLit: litStage == 3) {
            HStack(spacing: 6) {
                Text("primary")
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                EnvironmentBadge(environment: .paper)
            }
            StatusBadge("Filled", tone: .positive)
            Text(L10n.string("%lld %@ at %@", Int64(12), "NVDA", "$121.38"))
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
        }
    }
}
