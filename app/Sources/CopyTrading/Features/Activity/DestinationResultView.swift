import DesktopCore
import SwiftUI

/// One account's handling of one post: the outcome, then each order's steps.
struct DestinationResultView: View {
    let destination: DestinationActivity

    private var outcome: DestinationOutcome { DestinationOutcome(destination) }

    private var instructionDetails: [DestinationInstructionDetail] {
        DestinationInstructionDetails.rows(for: destination, summary: outcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(destination.accountID)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let environment = TradingEnvironment(rawValue: destination.environment) {
                    EnvironmentBadge(environment: environment)
                }
            }
            OutcomeBadge(outcome: outcome)
            Text(outcome.detail)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(destination.orders) { order in
                OrderSteps(order: order)
            }
            if !instructionDetails.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DestinationInstructionDetails.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Palette.tertiaryInk)
                    ForEach(instructionDetails) { detail in
                        Text(detail.value)
                            .font(.callout)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .textSelection(.enabled)
    }
}
