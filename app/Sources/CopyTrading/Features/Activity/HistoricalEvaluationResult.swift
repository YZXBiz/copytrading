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
            SheetGroup {
                SheetRow(
                    title: L10n.string(Humanize.code(evaluation.decision)), hint: EvaluationNote.text(evaluation, post: post)
                ) { EmptyView() }
                ForEach(Array(evaluation.instructions.enumerated()), id: \.offset) { _, instruction in
                    SheetRow(
                        title: L10n.string(
                            "%@ %@ at %@", L10n.string(Humanize.code(instruction.action.rawValue)), instruction.symbol,
                            instruction.price.map { Humanize.usd($0) } ?? L10n.string("the market price"))
                    ) { EmptyView() }
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
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("activity.historicalEvaluation.noOrder")
        }
    }
}
