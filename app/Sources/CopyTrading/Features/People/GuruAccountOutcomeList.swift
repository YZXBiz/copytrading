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
                    // A long account name shortens in the middle rather than breaking at its hyphens;
                    // what happened keeps its words.
                    Text(outcome.accountID)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(outcome.summary)
                        .foregroundStyle(outcome.kind == .waiting ? Palette.amber : Palette.tertiaryInk)
                        .lineLimit(2)
                        .layoutPriority(1)
                        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(DesignTokens.caption)
    }
}
