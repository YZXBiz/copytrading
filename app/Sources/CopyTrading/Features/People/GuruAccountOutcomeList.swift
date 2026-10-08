import SwiftUI

/// What each account did with a post, one line each: the account, a coloured mark, a few words.
struct GuruAccountOutcomeList: View {
    let outcomes: [GuruAccountOutcome]
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            if outcomes.isEmpty {
                Text(L10n.string("No account acted on it"))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            ForEach(outcomes) { outcome in
                HStack(spacing: 6) {
                    Text(outcome.accountID)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.secondaryInk)
                    GuruOutcomeMark(kind: outcome.kind)
                    Text(outcome.summary)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(DesignTokens.caption)
    }
}
