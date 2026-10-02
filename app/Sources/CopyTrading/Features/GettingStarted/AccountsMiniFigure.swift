import SwiftUI

/// Accounts in miniature: a paper account taking entries, and how much of a limit it has used.
struct AccountsMiniFigure: View {
    var body: some View {
        GuideFigure(
            description: L10n.string(
                "Example of Accounts: the primary paper account is taking entries and has used $40 of its $250 daily loss cap."),
            showsWindowControls: false
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("primary")
                        .font(DesignTokens.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                    EnvironmentBadge(environment: .paper)
                }
                Pill(text: "Taking entries", symbol: StatusTone.positive.symbol, tint: StatusTone.positive.color)
                LimitMeter(title: "Daily loss cap", used: 40, limit: 250)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.page, in: .rect(cornerRadius: 10))
        }
    }
}
