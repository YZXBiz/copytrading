import DesktopCore
import SwiftUI

/// What reading an earlier post again decided, each call it found, and what each account would have
/// done, in plain words; the model's own notes stay behind their reasons.
struct HistoricalEvaluationResult: View {
    let evaluation: ProfileEvaluation
    /// The post read, so a note that only repeats it is left out.
    let post: String

    var body: some View {
        SheetSection(L10n.string("Simulated result · no orders")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string(Humanize.code(evaluation.decision)))
                    .font(DesignTokens.rowTitle)
                    .foregroundStyle(Palette.ink)
                if let note = EvaluationNote.text(evaluation, post: post) {
                    Text(note)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                ForEach(Array(evaluation.instructions.enumerated()), id: \.offset) { _, instruction in
                    Text(
                        L10n.string(
                            "%@ %@ at %@", L10n.string(Humanize.code(instruction.action.rawValue)), instruction.symbol,
                            instruction.price.map { Humanize.usd($0) } ?? L10n.string("the market price"))
                    )
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                }
                ForEach(Array(evaluation.destinations.enumerated()), id: \.offset) { _, destination in
                    SheetRow(
                        title: destination.accountID,
                        hint: destination.budgetUSD == nil ? Reason.text(destination.reason) : nil
                    ) {
                        if let budget = destination.budgetUSD {
                            Text(
                                destination.action == .buy
                                    ? L10n.string("Buy %@ of %@", Humanize.dollars(budget), destination.symbol)
                                    : L10n.string("Sell %@", destination.symbol)
                            )
                            .font(DesignTokens.bodyText)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
                ForEach(evaluation.reviewReasons, id: \.self) { reason in
                    Text(Reason.text(reason))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.amber)
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("activity.historicalEvaluation.noOrder")
        }
    }
}
