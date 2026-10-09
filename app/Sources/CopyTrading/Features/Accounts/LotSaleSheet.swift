import DesktopCore
import SwiftUI

/// Selling shares from one lot, in the page's own register: the account in tracked capitals, a big
/// "Sell WMT", where the lot came from, then a quarter, a half, three quarters, or all of it with a
/// live line saying what that comes to. One black button checks the sale with the broker, the
/// next sends it. Nothing reaches the broker until then, and a live account asks for Touch ID first.
struct LotSaleSheet: View {
    @State private var flow: LotSaleFlow
    let operations: (any LotSaleOperations)?
    let confirmOwner: () async throws -> Void
    let finished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        flow: LotSaleFlow, operations: (any LotSaleOperations)?, confirmOwner: @escaping () async throws -> Void,
        finished: @escaping () -> Void
    ) {
        _flow = State(initialValue: flow)
        self.operations = operations
        self.confirmOwner = confirmOwner
        self.finished = finished
    }

    private var target: LotSaleTarget { flow.target }

    /// The chips' parts of the lot.
    private static let parts: [(title: String, part: Decimal)] = [
        ("¼", Decimal(string: "0.25")!), ("½", Decimal(string: "0.5")!), ("¾", Decimal(string: "0.75")!), ("", 1),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch flow.phase {
                case .choosing, .checking:
                    choosing
                case .reviewing(let preview), .selling(let preview):
                    review(preview)
                case .finished(let result):
                    outcome(result)
                }
            }
            .padding(.top, 30)
            if let problem = flow.problem {
                Label(L10n.string(problem), systemImage: "exclamationmark.circle")
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }
            Spacer(minLength: 34)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: 480)
        .frame(minHeight: 400)
        .background(Palette.page)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: flow.phase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Eyebrow(target.accountID)
                Eyebrow(" · ")
                Eyebrow(
                    L10n.string(target.environment == .live ? "Live" : "Paper"),
                    color: target.environment == .live ? .orange : Palette.tertiaryInk)
            }
            Text(L10n.string("Sell %@", target.symbol))
                .font(DisplayFont.font(size: 40, weight: .medium, relativeTo: .largeTitle))
                .tracking(DesignTokens.entityTitleTracking)
                .foregroundStyle(Palette.ink)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 2) {
                Text(origin)
                if let price = Decimal(engine: target.lot.averagePrice) {
                    Text(L10n.string("Bought at %@", price.formatted(.currency(code: "USD"))))
                }
            }
            .font(DesignTokens.lede)
            .tracking(DesignTokens.ledeTracking)
            .monospacedDigit()
            .foregroundStyle(Palette.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        }
    }

    /// "From Zhao’s post, Oct 9 at 7:47 AM"
    @MainActor private var origin: String {
        let who = target.guruName.map { L10n.string("From %@’s post", $0) } ?? L10n.string("From a post")
        return target.lot.postedAt.map { L10n.string("%@, %@", who, Humanize.postTime($0)) } ?? who
    }

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 26) {
                ForEach(Self.parts, id: \.part) { chip in
                    let amount = flow.amount(chip.part)
                    LotSaleShareChip(
                        title: chip.part == 1 ? L10n.string("All") : chip.title,
                        isSelected: flow.shares == amount && amount > 0
                    ) {
                        flow.shares = amount
                    }
                    .disabled(amount <= 0 || flow.phase == .checking)
                    .accessibilityLabel(L10n.string("Sell %@ shares", PositionRow.quantity(amount)))
                    .accessibilityIdentifier("lotSale.part.\(chip.part)")
                }
            }
            preview
                .padding(.top, 22)
            Text(
                operations == nil
                    ? L10n.string("The engine is stopped, so nothing can be sold right now. Start it from the banner or Settings.")
                    : L10n.string(
                        "CopyTrading checks the price, the market session, and your account before showing what the sale would do.")
            )
            .font(DesignTokens.caption)
            .foregroundStyle(operations == nil ? Palette.ink : Palette.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
        }
    }

    /// What the chosen part comes to at today's price, as it changes: "0.44 of 0.885 shares", then
    /// "About $49.01 at $110.75" and what those shares gained or lost.
    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("%@ of %@ sh", PositionRow.quantity(flow.shares), PositionRow.quantity(flow.remaining)))
                .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText(value: flow.shares.doubleValue))
            if let price = target.currentPrice {
                HStack(spacing: 8) {
                    Text(
                        L10n.string(
                            "About %@ at %@", (flow.shares * price).formatted(.currency(code: "USD")),
                            price.formatted(.currency(code: "USD")))
                    )
                    .foregroundStyle(Palette.secondaryInk)
                    if let bought = Decimal(engine: target.lot.averagePrice) {
                        MoneyText(value: flow.shares * (price - bought), style: .change, font: DesignTokens.bodyText)
                    }
                }
                .font(DesignTokens.bodyText)
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lotSale.shares")
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: flow.shares)
    }

    @ViewBuilder
    private func review(_ preview: LotSalePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                HStack(alignment: .top, spacing: 12) {
                    OutcomeMark(tone: .inactive).padding(.top, 4)
                    Text(L10n.string("This sale can’t go out right now:"))
                        .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preview.reasons, id: \.self) { reason in
                        Text(Reason.text(reason))
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(DesignTokens.bodyText)
                .padding(.leading, 27)
            }
        }
    }

    @MainActor private func saleSentence(_ plan: ManualOrderPlan, _ preview: LotSalePreview) -> String {
        let quantity = Decimal(engine: plan.quantity) ?? 0
        let bid = preview.freshPrice.flatMap { Decimal(engine: $0) }
        let noun = L10n.string(quantity == 1 ? "share" : "shares")
        let shares = L10n.string("%@ %@ of %@", quantity.formatted(), noun, plan.symbol)
        guard let limit = plan.limitPrice.flatMap({ Decimal(engine: $0) }) else { return shares }
        let sentence = L10n.string(
            "Sells %@ with a limit order at %@. It fills at that price or better, or not at all.",
            shares, limit.formatted(.currency(code: "USD")))
        guard let bid else { return sentence }
        let proceeds = (quantity * bid).formatted(.currency(code: "USD"))
        return L10n.sentences([
            sentence,
            L10n.string(
                "At today’s bid of %@, that comes to about %@.", bid.formatted(.currency(code: "USD")), proceeds),
        ])
    }

    @ViewBuilder
    private func outcome(_ result: LotSaleResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                OutcomeMark(tone: outcomeTone(result)).padding(.top, 4)
                Text(outcomeTitle(result))
                    .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lotSale.outcome")
            Text(outcomeDetail(result))
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 27)
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
        case "rejected": return Reason.text(result.reason)
        default: return Reason.text(result.reason ?? result.status)
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

    /// A quiet way out on the left, the one black action on the right.
    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            switch flow.phase {
            case .choosing, .checking:
                quiet(L10n.string("Cancel"), action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(
                    flow.phase == .checking
                        ? L10n.string("Checking…")
                        : L10n.string("Sell %@ %@…", PositionRow.quantity(flow.shares), target.symbol)
                ) {
                    Task { await flow.review(using: operations) }
                }
                .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 20))
                .disabled(!flow.canReview || operations == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("lotSale.review.button")
            case .reviewing(let preview):
                quiet(L10n.string("Back")) { flow.startOver() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if preview.plan != nil {
                    Button(sellTitle(preview)) {
                        Task { await flow.confirm(using: operations, confirmOwner: confirmOwner) }
                    }
                    .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 20))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("lotSale.sell")
                }
            case .selling:
                Spacer()
                ProgressView().controlSize(.small)
                Text(L10n.string("Sending…")).foregroundStyle(Palette.secondaryInk)
            case .finished(let result):
                if result.status == "rejected" {
                    quiet(L10n.string("Review Again")) { flow.startOver() }
                }
                Spacer()
                Button(L10n.string("Done")) {
                    finished()
                    dismiss()
                }
                .buttonStyle(PageButtonStyle(isProminent: true, horizontalPadding: 20))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func quiet(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(QuietPressButtonStyle())
            .font(DesignTokens.bodyText.weight(.medium))
            .foregroundStyle(Palette.secondaryInk)
    }

    @MainActor private func sellTitle(_ preview: LotSalePreview) -> String {
        let quantity = preview.plan.flatMap { Decimal(engine: $0.quantity) } ?? flow.shares
        return L10n.string(
            target.asksForOwner ? "Sell %@ %@ with Touch ID" : "Sell %@ %@",
            quantity.formatted(), target.symbol
        )
    }
}
