import SwiftUI

/// What each account did with a post, one quiet line each: the account, then a few words. Only a
/// call waiting on the owner carries colour; the words say the rest.
struct GuruAccountOutcomeList: View {
    let outcomes: [GuruAccountOutcome]
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 5) {
            if outcomes.isEmpty {
                Text(L10n.string("No account acted on it"))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            ForEach(outcomes) { outcome in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(outcome.accountID)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(outcome.summary)
                        .foregroundStyle(outcome.kind == .waiting ? Palette.amber : Palette.tertiaryInk)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(DesignTokens.caption)
    }
}
