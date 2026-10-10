import DesktopCore
import SwiftUI

/// What to know before copying, each beside the control or mark it is about. Each note opens in
/// bold, so space alone parts them.
struct GuideBeforeYouGoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GuideSafetyRow(
                text:
                    "**Start on paper.** Paper accounts trade pretend money at real prices. A live account asks for Touch ID before it starts."
            ) {
                HStack(spacing: 8) {
                    EnvironmentBadge(environment: .paper)
                    EnvironmentBadge(environment: .live)
                }
            }
            GuideSafetyRow(
                text:
                    "**A sleeping Mac copies nothing.** Keep it plugged in and awake, with CopyTrading open, while the market is. A closed MacBook lid sleeps it unless a display is connected."
            ) {
                Label(L10n.string("Keep this Mac awake"), systemImage: "moon.zzz")
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
            }
            GuideSafetyRow(
                text:
                    "**Discord's terms** don't allow automating a personal account. Use a separate account that only joins your gurus' servers."
            ) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.title2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            GuideSafetyRow(text: "**Your AI service bills you** for each post it reads, usually a fraction of a cent.") {
                Image(systemName: "dollarsign.circle")
                    .font(.title2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            GuideSafetyRow(
                text:
                    "**It copies; it doesn't judge.** No advice and no stop-losses. The daily loss cap stops buying, not selling. **Pause Copying** stops everything at once."
            ) {
                Label(L10n.string("Pause Copying"), systemImage: "pause.fill")
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Palette.well, in: .capsule)
            }
        }
    }
}
