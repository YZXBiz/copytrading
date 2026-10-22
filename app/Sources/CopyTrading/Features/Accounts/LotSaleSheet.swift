import DesktopCore
import SwiftUI

/// Selling shares from one lot, as every sheet reads: "Sell WMT" over the account, the lot it
/// came from, then how much of it with a live line on what that comes to. One black button checks
/// the sale with the broker, the next sends it. Nothing reaches the broker until then, and a live
/// account asks for Touch ID first.
struct LotSaleSheet: View {
    @State private var flow: LotSaleFlow
    /// The sale is held for a few seconds before it leaves, so it can be undone.
    @State private var isHolding = false
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

    /// The parts of the lot to choose from.
    private static let parts: [(title: String, part: Decimal)] = [
        ("¼", Decimal(string: "0.25")!), ("½", Decimal(string: "0.5")!), ("¾", Decimal(string: "0.75")!), ("All", 1),
    ]

    var body: some View {
        SheetScaffold(
            title: L10n.string("Sell %@", target.symbol),
            lede: L10n.string("%@ · %@", target.accountID, L10n.string(target.environment == .live ? "Live" : "Paper")),
            scrolls: false
        ) {
            lotSection
            switch flow.phase {
            case .choosing, .checking:
                choosing
            case .reviewing(let preview), .selling(let preview):
                review(preview)
            case .finished(let result):
                outcome(result)
            }
            if let problem = flow.problem {
                Callout(L10n.string(problem), tone: .caution)
            }
        } leading: {
            leading
        } actions: {
            actions
        }
        .frame(width: 520)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: flow.phase)
    }

    /// Where the shares came from and what they cost.
    private var lotSection: some View {
        SheetSection(L10n.string("Lot")) {
            SheetGroup {
                SheetRow(title: origin, isReading: true) {
                    if let price = Decimal(engine: target.lot.averagePrice) {
                        Text(L10n.string(posts > 1 ? "Average cost %@" : "Bought at %@", price.formatted(.currency(code: "USD"))))
                            .font(DesignTokens.bodyText)
                            .foregroundStyle(Palette.secondaryInk)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    /// The posts whose buys still hold shares in the lot.
    private var posts: Int {
        Set(target.lot.buys.map { $0.sourceID ?? $0.orderID }).count
    }

    /// "From Zhao’s post, Oct 9 at 7:47 AM", or "From Zhao’s 2 posts" for a lot of several buys.
    @MainActor private var origin: String {
        guard posts <= 1 else {
            let count = Humanize.count(posts, "post")
            return target.guruName.map { L10n.string("From %@’s %@", $0, count) } ?? L10n.string("From %@", count)
        }
        let buy = target.lot.buys.first
        let who = target.guruName.map { L10n.string("From %@’s post", $0) } ?? L10n.string("From a post")
        return (buy?.postedAt ?? target.lot.postedAt).map { L10n.string("%@, %@", who, Humanize.postTime($0)) } ?? who
    }

    /// The parts the lot can be split into; a part too small to sell is left out.
    private var choices: [(title: String, part: Decimal)] {
        Self.parts.filter { flow.amount($0.part) > 0 }
    }

    /// The chosen part, while the shares are exactly one of them.
    private var part: Binding<Decimal> {
        Binding(
            get: { choices.first { flow.amount($0.part) == flow.shares }?.part ?? 0 },
            set: { flow.shares = flow.amount($0) })
    }

    private var choosing: some View {
        SheetSection(L10n.string("Amount")) {
            SheetGroup {
                SheetRow(title: L10n.string("Sell"), labelsControl: true) {
                    Picker(L10n.string("Sell"), selection: part) {
                        ForEach(choices, id: \.part) { choice in
                            Text(L10n.string(choice.title)).tag(choice.part)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(flow.phase == .checking)
                    .accessibilityIdentifier("lotSale.part")
                }
                preview
            }
        } footer: {
            Text(
                operations == nil
                    ? L10n.string("The engine is stopped, so nothing can be sold right now. Start it from the banner or Settings.")
                    : L10n.string("The price, market session, and account are checked before anything is sent.")
            )
            .foregroundStyle(operations == nil ? Palette.ink : Palette.tertiaryInk)
        }
    }

    /// What the chosen part comes to at today's price, as it changes: "0.44 of 0.885 shares", then
    /// "About $49.01 at $110.75" and what those shares gained or lost.
    private var preview: some View {
        SheetRow(
            title: flow.sharesLine,
            hint: target.currentPrice.map {
                L10n.string("About %@ at %@", (flow.shares * $0).formatted(.currency(code: "USD")), $0.formatted(.currency(code: "USD")))
            },
            isReading: true
        ) {
            if let price = target.currentPrice, let bought = Decimal(engine: target.lot.averagePrice) {
                MoneyText(value: flow.shares * (price - bought), style: .change, font: DesignTokens.bodyText)
                    .monospacedDigit()
            }
        }
        .contentTransition(.numericText(value: flow.shares.doubleValue))
        .accessibilityIdentifier("lotSale.shares")
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: flow.shares)
    }

    @ViewBuilder
    private func review(_ preview: LotSalePreview) -> some View {
        if let plan = preview.plan {
            SheetSection(L10n.string("Review")) {
                SheetGroup {
                    Text(saleSentence(plan, preview))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("lotSale.review")
                }
            } footer: {
                Text(L10n.string("Prices are checked again the moment you press Sell. If anything changed, nothing is sent."))
            }
        } else {
            SheetSection(L10n.string("This sale can’t go out right now")) {
                SheetGroup {
                    ForEach(preview.reasons, id: \.self) { reason in
                        SheetRow(title: Reason.text(reason), isReading: true) { EmptyView() }
                    }
                }
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

    private func outcome(_ result: LotSaleResult) -> some View {
        SheetSection(L10n.string("Result")) {
            SheetGroup {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    OutcomeMark(tone: outcomeTone(result))
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcomeTitle(result))
                            .font(DesignTokens.rowTitle)
                            .foregroundStyle(Palette.ink)
                        Text(outcomeDetail(result))
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lotSale.outcome")
            }
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

    /// The bar's way out: Cancel, Back, or Review Again; while a sale is held, the hold and Undo
    /// take the whole bar.
    @ViewBuilder
    private var leading: some View {
        switch flow.phase {
        case .choosing, .checking:
            Button(L10n.string("Cancel"), action: dismiss.callAsFunction)
                .buttonStyle(SheetButtonStyle())
                .keyboardShortcut(.cancelAction)
        case .reviewing(let preview) where isHolding:
            OrderHold(
                title: sellTitle(preview), seconds: OrderHold.chosenSeconds,
                send: {
                    isHolding = false
                    Task { await flow.confirm(using: operations, confirmOwner: confirmOwner) }
                },
                undo: { isHolding = false })
        case .reviewing:
            Button(L10n.string("Back")) { flow.startOver() }
                .buttonStyle(SheetButtonStyle())
                .keyboardShortcut(.cancelAction)
        case .selling:
            EmptyView()
        case .finished(let result):
            if result.status == "rejected" {
                Button(L10n.string("Review Again")) { flow.startOver() }
                    .buttonStyle(SheetButtonStyle())
            }
        }
    }

    /// The bar's one black action: check the sale, send it, or close.
    @ViewBuilder
    private var actions: some View {
        switch flow.phase {
        case .choosing, .checking:
            Button(
                flow.phase == .checking
                    ? L10n.string("Checking…")
                    : L10n.string("Sell %@ %@…", PositionRow.quantity(flow.shares), target.symbol)
            ) {
                Task { await flow.review(using: operations) }
            }
            .buttonStyle(SheetButtonStyle(isPrimary: true))
            .disabled(!flow.canReview || operations == nil)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("lotSale.review.button")
        case .reviewing(let preview) where !isHolding && preview.plan != nil:
            Button(sellTitle(preview)) {
                if OrderHold.chosenSeconds > 0 {
                    isHolding = true
                } else {
                    Task { await flow.confirm(using: operations, confirmOwner: confirmOwner) }
                }
            }
            .buttonStyle(SheetButtonStyle(isPrimary: true))
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("lotSale.sell")
        case .reviewing:
            EmptyView()
        case .selling:
            ProgressView().controlSize(.small)
            Text(L10n.string("Sending…")).foregroundStyle(Palette.secondaryInk)
        case .finished:
            Button(L10n.string("Done")) {
                finished()
                dismiss()
            }
            .buttonStyle(SheetButtonStyle(isPrimary: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    @MainActor private func sellTitle(_ preview: LotSalePreview) -> String {
        let quantity = preview.plan.flatMap { Decimal(engine: $0.quantity) } ?? flow.shares
        return L10n.string(
            target.asksForOwner ? "Sell %@ %@ with Touch ID" : "Sell %@ %@",
            quantity.formatted(), target.symbol
        )
    }
}

#if DEBUG
    #Preview("Sell SOXL") {
        let lot = try! JSONDecoder().decode(
            AccountLotView.self,
            from: Data(
                """
                {"lot_id":"copy-lot","source_id":"discord:demo:1","guru_id":"zhao","posted_at":"2026-10-21T14:30:00Z",\
                "excerpt":"93.2出一半","bought_at":"2026-10-21T14:30:05Z","original_qty":"2.779841","remaining_qty":"2.779841",\
                "average_price":"89.37","buys":[]}
                """.utf8))
        return LotSaleSheet(
            flow: LotSaleFlow(
                target: LotSaleTarget(
                    accountID: "zhap-account-2", environment: .paper, symbol: "SOXL", lot: lot, guruName: "Zhao",
                    currentPrice: 93.20)),
            operations: nil, confirmOwner: {}, finished: {})
    }
#endif
