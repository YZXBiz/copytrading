import SwiftUI

/// The controls that keep money safe, each shown as it looks in the app.
struct GuideSafetySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GuideSafetyRow(
                text:
                    "**Pause Copying** in the toolbar stops reading new posts and placing orders for every account, from any screen. The menu bar has it too."
            ) {
                Label(L10n.string("Pause Copying"), systemImage: "pause.fill")
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Palette.page, in: .capsule)
                    .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
            Divider()
            GuideSafetyRow(
                text:
                    "Every account has its own **limits**: per order, per symbol, in total, and a daily loss cap. A call that would cross one is skipped, and Activity says why."
            ) {
                LimitMeter(title: "Daily loss cap", used: 40, limit: 250)
            }
            Divider()
            GuideSafetyRow(
                text:
                    "**Paper** accounts trade pretend money. **Live** accounts are marked in orange everywhere, and starting one always asks you first."
            ) {
                HStack(spacing: 8) {
                    EnvironmentBadge(environment: .paper)
                    EnvironmentBadge(environment: .live)
                }
            }
            Divider()
            GuideSafetyRow(
                text:
                    "New accounts start with **entries off**, so nothing is bought until you choose **Enable Entries** in Accounts. Shares you already hold are never sold by CopyTrading."
            ) {
                Pill(text: L10n.string("Entries off"), symbol: StatusTone.inactive.symbol, tint: StatusTone.inactive.color)
            }
            Divider()
            GuideSafetyRow(
                text:
                    "**Lock** hides your accounts, posts, and keys until you unlock with Touch ID. Every key stays in your Mac's Keychain."
            ) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Palette.accent, in: .circle)
            }
        }
    }
}
