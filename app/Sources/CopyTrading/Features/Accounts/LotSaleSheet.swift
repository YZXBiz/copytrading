import DesktopCore
import SwiftUI

/// Selling shares from one lot: how many, what the sale would do at today's price, and a single
/// confirmation. Nothing reaches the broker until Sell is pressed, and a live account asks for
/// Touch ID first.
struct LotSaleSheet: View {
    @State private var flow: LotSaleFlow
    let operations: (any LotSaleOperations)?
    let confirmOwner: () async throws -> Void
    let finished: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        target: LotSaleTarget, operations: (any LotSaleOperations)?, confirmOwner: @escaping () async throws -> Void,
        finished: @escaping () -> Void
    ) {
        _flow = State(initialValue: LotSaleFlow(target: target))
        self.operations = operations
        self.confirmOwner = confirmOwner
        self.finished = finished
    }

    private var target: LotSaleTarget { flow.target }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            switch flow.phase {
            case .choosing, .checking:
                choosing
            case .reviewing(let preview), .selling(let preview):
                review(preview)
            case .finished(let result):
                outcome(result)
            }
            if let problem = flow.problem {
                Callout(problem, tone: .caution)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(26)
        .frame(width: 460)
        .frame(minHeight: 380)
        .animation(.smooth(duration: 0.25), value: flow.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L10n.string("Sell %@", target.symbol))
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if target.environment == .live {
                    Text(L10n.string("Live"))
                        .font(DesignTokens.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.14), in: .capsule)
                }
            }
            Text(origin)
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor private var origin: String {
        let who = target.guruName.map { L10n.string("%@’s post", $0) } ?? L10n.string("a post")
        let when = target.lot.postedAt.map { L10n.string(" on %@", Humanize.timestamp($0)) } ?? ""
        let price = Decimal(engine: target.lot.averagePrice).map { L10n.string(" at %@", $0.formatted(.currency(code: "USD"))) } ?? ""
        return L10n.string("%@ shares left from %@%@, bought%@ in %@.", flow.remaining.formatted(), who, when, price, target.accountID)
    }

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("How many shares?"))
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                TextField(L10n.string("Shares"), value: $flow.shares, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .accessibilityLabel(L10n.string("Shares to sell"))
                    .accessibilityIdentifier("lotSale.shares")
                Button(L10n.string("All %@", flow.remaining.formatted())) { flow.shares = flow.remaining }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                if flow.remaining >= 2 {
                    Button(L10n.string("Half")) { flow.shares = half(flow.remaining) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
            if flow.shares > flow.remaining {
                Text(L10n.string("That is more than this lot holds."))
                    .font(DesignTokens.caption)
                    .foregroundStyle(.orange)
            }
            Text(
                operations == nil
                    ? L10n.string("The engine is stopped, so nothing can be sold right now. Start it from the banner or Settings.")
                    : L10n.string(
                        "CopyTrading checks the price, the market session, and your account before showing what the sale would do.")
            )
            .font(DesignTokens.caption)
            .foregroundStyle(operations == nil ? .orange : Palette.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func review(_ preview: LotSalePreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plan = preview.plan {
                Text(saleSentence(plan, preview))
                    .font(DesignTokens.documentBody)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lotSale.review")
                Text(L10n.string("Prices are checked again the moment you press Sell. If anything changed, nothing is sent."))
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.string("This sale can’t go out right now:"))
                    .font(DesignTokens.documentBody)
                    .foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preview.reasons, id: \.self) { reason in
                        Label(Reason.text(reason), systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .font(DesignTokens.bodyText)
            }
        }
    }

    @MainActor private func saleSentence(_ plan: ManualOrderPlan, _ preview: LotSalePreview) -> String {
        let quantity = Decimal(engine: plan.quantity) ?? 0
        let bid = preview.freshPrice.flatMap { Decimal(engine: $0) }
        let noun = L10n.string(quantity == 1 ? "share" : "shares")
        let shares = L10n.string("%@ %@ of %@", quantity.formatted(), noun, plan.symbol)
        if plan.type == "limit", let limit = plan.limitPrice.flatMap({ Decimal(engine: $0) }) {
            return L10n.string(
                "Sells %@ with a limit order at %@, since the market is outside regular hours. It fills at that price or better, or not at all.",
                shares, limit.formatted(.currency(code: "USD"))
            )
        }
        guard let bid else { return L10n.string("Sells %@ at the market price.", shares) }
        let proceeds = (quantity * bid).formatted(.currency(code: "USD"))
        return L10n.string(
            "Sells %@ at the market price. At today’s bid of %@, that comes to about %@.",
            shares, bid.formatted(.currency(code: "USD")), proceeds
        )
    }

    @ViewBuilder
    private func outcome(_ result: LotSaleResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(outcomeTitle(result), systemImage: outcomeTone(result).symbol)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(outcomeTone(result) == .positive ? Palette.ink : outcomeTone(result).color)
                .accessibilityIdentifier("lotSale.outcome")
            Text(outcomeDetail(result))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor private func outcomeTitle(_ result: LotSaleResult) -> String {
        let filled = Decimal(engine: result.filledQty) ?? 0
        switch result.status {
        case "filled":
            let price =
                result.filledAvgPrice.flatMap { Decimal(engine: $0) }.map { L10n.string(" at %@", $0.formatted(.currency(code: "USD"))) }
                ?? ""
            return L10n.string("Sold %@ %@%@", filled.formatted(), target.symbol, price)
        case "partially_filled": return L10n.string("Sold %@ so far", filled.formatted())
        case "accepted", "prepared": return L10n.string("Your sale is in")
        case "uncertain": return L10n.string("Waiting to hear from the broker")
        case "rejected": return L10n.string("Nothing was sent")
        default: return L10n.string(Humanize.code(result.status))
        }
    }

    @MainActor private func outcomeDetail(_ result: LotSaleResult) -> String {
        switch result.status {
        case "filled": return L10n.string("Those shares are out of this lot. Activity shows the sale beside the post that bought them.")
        case "partially_filled", "accepted", "prepared":
            return L10n.string("The broker has the order. Accounts updates as it fills.")
        case "uncertain":
            return L10n.string("CopyTrading did not get the broker’s answer. It checks again on its own and never sends the order twice.")
        case "rejected": return L10n.string(Reason.text(result.reason))
        default: return L10n.string(Reason.text(result.reason ?? result.status))
        }
    }

    private func outcomeTone(_ result: LotSaleResult) -> StatusTone {
        switch result.status {
        case "filled": .positive
        case "partially_filled", "accepted", "prepared": .neutral
        case "uncertain": .caution
        default: .critical
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            switch flow.phase {
            case .choosing, .checking:
                Button(L10n.string("Cancel"), action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string(flow.phase == .checking ? "Checking…" : "Review Sale")) {
                    Task { await flow.review(using: operations) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!flow.canReview || operations == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("lotSale.review.button")
            case .reviewing(let preview):
                Button(L10n.string("Back")) { flow.startOver() }
                    .keyboardShortcut(.cancelAction)
                if preview.plan != nil {
                    Button(sellTitle(preview)) {
                        Task { await flow.confirm(using: operations, confirmOwner: confirmOwner) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("lotSale.sell")
                }
            case .selling:
                ProgressView().controlSize(.small)
                Text(L10n.string("Sending…")).foregroundStyle(Palette.secondaryInk)
            case .finished(let result):
                if result.status == "rejected" {
                    Button(L10n.string("Review Again")) { flow.startOver() }
                }
                Button(L10n.string("Done")) {
                    finished()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Half the lot in whole shares, rounded down.
    private func half(_ value: Decimal) -> Decimal {
        var input = value / 2
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }

    @MainActor private func sellTitle(_ preview: LotSalePreview) -> String {
        let quantity = preview.plan.flatMap { Decimal(engine: $0.quantity) } ?? flow.shares
        return L10n.string(
            target.environment == .live ? "Sell %@ %@ with Touch ID" : "Sell %@ %@",
            quantity.formatted(), target.symbol
        )
    }
}
