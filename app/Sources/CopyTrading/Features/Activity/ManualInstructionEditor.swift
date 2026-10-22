import DesktopCore
import SwiftUI

/// What should happen, as one group of rows: Buy or Sell, then the stock (for a sell, one
/// CopyTrading holds, with what is held as a note), how much, which buys a sell takes from, and
/// the price.
struct ManualInstructionEditor: View {
    @Binding var draft: ManualInstructionDraft
    /// What CopyTrading holds in the chosen accounts.
    let holdings: [ManualHolding]
    /// The broker's latest quote for the chosen stock; nil until one is asked for and answered.
    let quote: LiveQuote?
    /// Asks the broker again for the chosen stock's quote; nil while it is being asked.
    var refreshQuote: (() -> Void)?
    /// A full position for this guru in the one chosen account; nil when several are chosen.
    let fullPosition: TradingRouteConnection?
    /// That account's max per order, which caps any one buy; nil when several are chosen.
    let maxOrderUSD: Decimal?
    @FocusState private var focusedField: String?

    private var symbol: String { draft.symbol.trimmed.uppercased() }
    private var holding: ManualHolding? { holdings.first { $0.symbol == symbol } }

    var body: some View {
        SheetGroup {
            FormRow(label: L10n.string("Side")) {
                Picker(L10n.string("Side"), selection: Binding(get: { draft.isSell }, set: setSell)) {
                    Text(L10n.string("Buy")).tag(false)
                    Text(L10n.string("Sell")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("review.side")
            }
            FormRow(label: L10n.string("Stock"), note: holdingNote) { stock }
            FormRow(label: L10n.string("How much"), note: capNote) { amount }
            if draft.isSell, !buyPrices.isEmpty {
                FormRow(label: L10n.string("From")) { buys }
            }
            TimelineView(.periodic(from: .now, by: 10)) { context in
                FormRow(label: L10n.string("Price"), note: quoteNote(now: context.date)) { price(now: context.date) }
            }
        }
        .onChange(of: quote) { followMarket() }
        .onChange(of: draft.symbol) { followMarket() }
    }

    /// What is held of the chosen stock, under the Stock row of a sell.
    @MainActor private var holdingNote: String? {
        guard draft.isSell, let holding else { return nil }
        return L10n.string("You hold %@", detail(of: holding))
    }

    // MARK: Stock

    @ViewBuilder private var stock: some View {
        if draft.isSell {
            let named = !symbol.isEmpty && holding == nil
            if holdings.isEmpty, !named {
                Text(L10n.string("Nothing CopyTrading bought is held in these accounts."))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                FlowRow(spacing: 8, lineSpacing: 8) {
                    ForEach(holdings) { held in
                        FormChoice(title: held.symbol, isOn: held.symbol == symbol) {
                            pick(held.symbol)
                        }
                        .accessibilityIdentifier("review.stock.\(held.symbol)")
                    }
                    if named {
                        FormChoice(title: symbol, detail: L10n.string("Not held"), isOn: true) {}
                    }
                }
            }
        } else {
            TextField(
                L10n.string("Ticker"), text: $draft.symbol,
                prompt: Text(L10n.string("Type a ticker")).foregroundStyle(Palette.tertiaryInk)
            )
            .focused($focusedField, equals: "symbol")
            .accessibilityLabel(L10n.string("Symbol"))
            .sheetInput(width: DesignTokens.sheetNumberWidth)
            .accessibilityIdentifier("review.symbol")
        }
    }

    @MainActor private func detail(of held: ManualHolding) -> String {
        let shares = Humanize.shares(held.shares)
        guard let value = held.value else { return shares }
        return L10n.string("%@ · %@", shares, Humanize.usd(value))
    }

    // MARK: Amount

    /// The usual buy sizes, with those the max per order makes the same merged into one.
    private var buySizes: [BuySize] { BuySize.choices(fullPosition: fullPosition, maxOrderUSD: maxOrderUSD) }

    /// A dollar amount the post named, and what it spends after the max per order.
    private var namedUSD: (asked: Decimal, spent: Decimal)? {
        guard !draft.isSell, let usd = Decimal(string: draft.usdAmount.trimmed), usd > 0 else { return nil }
        return (usd, fullPosition?.spentUSD(sourceFraction: nil, sourceUSD: usd, maxOrderUSD: maxOrderUSD) ?? usd)
    }

    @ViewBuilder private var amount: some View {
        FlowRow(spacing: 8, lineSpacing: 8) {
            if draft.isSell {
                ForEach(ManualInstructionDraft.sellShares, id: \.self) { share in
                    FormChoice(title: shareTitle(share), isOn: ManualInstructionDraft.sameShare(share, draft.fraction)) {
                        draft.fraction = share
                    }
                    .accessibilityIdentifier("review.amount.\(Humanize.fraction(share))")
                }
                if !ManualInstructionDraft.sellShares.contains(where: { ManualInstructionDraft.sameShare($0, draft.fraction) }) {
                    FormChoice(title: shareTitle(draft.fraction), isOn: true) {}
                }
            } else {
                ForEach(buySizes, id: \.shares) { size in
                    FormChoice(
                        title: sizeTitle(size), detail: size.usd.map { Humanize.dollars("\($0)") },
                        isOn: draft.usdAmount.isEmpty && size.contains(draft.fraction)
                    ) {
                        draft.usdAmount = ""
                        // Already one of the sizes it stands for: keep the guru's own.
                        if !size.contains(draft.fraction) { draft.fraction = size.shares[0] }
                    }
                    .accessibilityIdentifier("review.amount.\(Humanize.fraction(size.shares[0].isEmpty ? "1" : size.shares[0]))")
                }
                if let namedUSD {
                    FormChoice(
                        title: Humanize.dollars("\(namedUSD.asked)"),
                        detail: namedUSD.spent < namedUSD.asked ? Humanize.dollars("\(namedUSD.spent)") : nil, isOn: true
                    ) {}
                } else if !draft.fraction.isEmpty, !buySizes.contains(where: { $0.contains(draft.fraction) }) {
                    // A size the post named that isn't one of the usual ones.
                    let usd = BuySize.choices([draft.fraction], fullPosition: fullPosition, maxOrderUSD: maxOrderUSD).first?.usd
                    FormChoice(title: shareTitle(draft.fraction), detail: usd.map { Humanize.dollars("\($0)") }, isOn: true) {}
                }
            }
        }
    }

    /// One plain line once the max per order cuts any size: "Bigger sizes stop at your $250 max
    /// per order."
    @MainActor private var capNote: String? {
        guard !draft.isSell, let maxOrderUSD else { return nil }
        let cut = buySizes.contains { $0.shares.count > 1 } || namedUSD.map { $0.spent < $0.asked } == true
        return cut ? L10n.string("Bigger sizes stop at your %@ max per order.", Humanize.dollars("\(maxOrderUSD)")) : nil
    }

    /// "⅙", "Full", or "¼ or more" for the sizes the max per order made the same.
    @MainActor private func sizeTitle(_ size: BuySize) -> String {
        let first = shareTitle(size.shares[0])
        return size.shares.count > 1 ? L10n.string("%@ or more", first) : first
    }

    @MainActor private func shareTitle(_ share: String) -> String {
        if share.isEmpty { return L10n.string("Full") }
        let fraction = Humanize.fraction(share)
        if fraction == "1" { return L10n.string(draft.isSell ? "All" : "Full") }
        let glyphs = ["1/6": "⅙", "1/4": "¼", "1/3": "⅓", "1/2": "½", "2/3": "⅔", "3/4": "¾", "1/5": "⅕", "1/8": "⅛"]
        return glyphs[fraction] ?? fraction
    }

    // MARK: Buys

    private var buyPrices: [Decimal] {
        var prices = holding?.buyPrices ?? []
        if let named = Decimal(string: draft.entryPrice.trimmed), !prices.contains(named) { prices.append(named) }
        return prices
    }

    private var buys: some View {
        FlowRow(spacing: 8, lineSpacing: 8) {
            FormChoice(title: L10n.string("Every buy"), isOn: draft.entryPrice.trimmed.isEmpty) { draft.entryPrice = "" }
            ForEach(buyPrices, id: \.self) { price in
                FormChoice(
                    title: L10n.string("The buy at %@", Humanize.dollars("\(price)")),
                    isOn: Decimal(string: draft.entryPrice.trimmed) == price
                ) { draft.entryPrice = "\(price)" }
            }
        }
    }

    // MARK: Price

    /// The guru's price, the market with its quote and ↻, and Limit, on one line. Each choice and
    /// what belongs to it wrap as one: ↻ never leaves Market, and the typed price never leaves
    /// Limit.
    @ViewBuilder private func price(now: Date) -> some View {
        FlowRow(spacing: 8, lineSpacing: 8) {
            if let post = Decimal(string: draft.postPrice.trimmed) {
                FormChoice(
                    title: Humanize.dollars("\(post)"), detail: L10n.string("the guru's price"),
                    isOn: draft.priceChoice == .guru
                ) { choose(.guru) }
                .accessibilityIdentifier("review.price.guru")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                FormChoice(title: L10n.string("Market"), detail: marketDetail(now: now), isOn: draft.priceChoice == .market) {
                    choose(.market)
                }
                // A buy at the market needs a live price to pay; a sell at the market never sends one.
                .disabled(!draft.isSell && livePrice(now: now) == nil)
                .accessibilityIdentifier("review.price.market")
                if LiveQuote.canQuote(symbol) { refreshButton }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                FormChoice(title: L10n.string("Limit"), isOn: draft.priceChoice == .limit) { choose(.limit) }
                    .accessibilityIdentifier("review.price.limit")
                if draft.priceChoice == .limit { limitField }
            }
        }
    }

    private var limitField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "$")
                .font(DesignTokens.bodyText)
                .foregroundStyle(Palette.secondaryInk)
            TextField(L10n.string("Limit price"), text: $draft.price, prompt: Text(verbatim: ""))
                .monospacedDigit()
                .focused($focusedField, equals: "price")
                .accessibilityLabel(L10n.string("Limit price"))
                .accessibilityIdentifier("review.price")
                .sheetInput(width: 96)
        }
    }

    /// Asks for the quote again, beside Market; a small spinner while the broker answers.
    @ViewBuilder private var refreshButton: some View {
        if let refreshQuote {
            Button(action: refreshQuote) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Get the latest price"))
            .accessibilityLabel(L10n.string("Get the latest price"))
            .accessibilityIdentifier("review.price.refresh")
        } else {
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel(L10n.string("Getting the latest price"))
        }
    }

    /// The live ask for a buy or bid for a sell.
    private func livePrice(now: Date) -> Decimal? {
        quote?.livePrice(isSell: draft.isSell, now: now)
    }

    /// "≈ $26.30 · 8:19 AM" while the quote is live; otherwise the note under the row says why
    /// there is none. A sell at the market goes just under the live bid.
    @MainActor private func marketDetail(now: Date) -> String? {
        if let detail = quote?.detail(isSell: draft.isSell, now: now) { return detail }
        return draft.isSell ? L10n.string("At the bid") : nil
    }

    /// Why Market has no price, under the row: "No live quote for CCL since 7:19 AM".
    @MainActor private func quoteNote(now: Date) -> String? {
        quote?.problem(isSell: draft.isSell, now: now)
    }

    // MARK: Changes

    private func choose(_ choice: PriceChoice) {
        draft.priceChoice = choice
        switch choice {
        case .guru:
            draft.price = draft.postPrice
        case .market:
            followMarket()
        case .limit:
            // Starts from the price it replaces, ready to edit.
            if draft.price.trimmed.isEmpty { draft.price = livePrice(now: .now).map { "\($0)" } ?? draft.postPrice }
            focusedField = "price"
        }
    }

    /// At the market, a buy pays the live ask and is not ready without one; a sell sends no price.
    private func followMarket() {
        guard draft.priceChoice == .market else { return }
        draft.price = draft.isSell ? "" : livePrice(now: .now).map { "\($0)" } ?? ""
    }

    private func setSell(_ sell: Bool) {
        guard draft.isSell != sell else { return }
        draft.isSell = sell
        draft.entryPrice = ""
        draft.usdAmount = ""
        draft.exitBasis = nil
        // The stock stays what the post named, or empty for the owner to pick: choosing Sell never
        // fills in a stock the post didn't name.
        if sell {
            if draft.fraction.isEmpty { draft.fraction = "1" }
        } else if draft.fraction == "1" {
            draft.fraction = ""
        }
        if draft.priceChoice != .limit { choose(ManualInstructionDraft.defaultChoice(postPrice: draft.postPrice)) }
    }

    private func pick(_ newSymbol: String) {
        draft.symbol = newSymbol
        draft.entryPrice = ""
    }
}
