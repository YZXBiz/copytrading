import SwiftUI

/// People in miniature: one guru, how their calls went, and where they are copied.
struct PeopleMiniFigure: View {
    var body: some View {
        GuideFigure(
            description: L10n.string("Example of People: Alex Chen made 12 calls, 9 filled, copied into the primary account."),
            showsWindowControls: false
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    GuruMonogram(name: "Alex Chen", size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Alex Chen")
                            .font(DesignTokens.bodyEmphasis)
                            .foregroundStyle(Palette.ink)
                        Text(L10n.string("Last post 3 minutes ago"))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                HStack(spacing: 14) {
                    GuideStat(value: 12, title: L10n.string("calls"))
                    GuideStat(value: 9, title: L10n.string("filled"))
                    GuideStat(value: 1, title: L10n.string("skipped"))
                }
                Chip(text: "primary", symbol: "arrow.right")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.page, in: .rect(cornerRadius: 10))
        }
    }
}
