import DesktopCore
import SwiftUI

/// What should happen, as one calm form: Buy or Sell on top, the only butter; then a row each for
/// the stock (for a sell, one CopyTrading holds, with what is held as a note), how much, which buys
/// a sell takes from, and the price.
struct ManualInstructionEditor: View {
    @Binding var draft: ManualInstructionDraft
    /// What CopyTrading holds in the chosen accounts.
    let holdings: [ManualHolding]
    /// The last price of every stock any account holds, by symbol.
    let marketPrices: [String: Decimal]
    /// The broker's latest quote for the chosen stock; nil until one is asked for and answered.
    let quote: LiveQuote?
    /// A full position for this guru in the one chosen account; nil when several are chosen.
    let fullPosition: TradingRouteConnection?
    /// "Trade 2 of 3" with Remove, when the sheet holds more than one.
    let position: (index: Int, count: Int)?
    let remove: () -> Void
    @State private var typesPrice = false
    @FocusState private var focusedField: String?

    private var symbol: String { draft.symbol.trimmed.uppercased() }
    private var holding: ManualHolding? { holdings.first { $0.symbol == symbol } }
    /// The live quote's ask for a buy or bid for a sell; a held stock's last price until it comes.
    private var marketPrice: Decimal? {
        if let quote { return quote.price(isSell: draft.isSell) }
        return holding?.price ?? marketPrices[symbol]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let position {
                HStack {
                    Text(L10n.string("Trade %lld of %lld", Int64(position.index + 1), Int64(position.count)))
                        .font(DesignTokens.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer()
                    Button(L10n.string("Remove"), action: remove)
                        .buttonStyle(QuietPressButtonStyle())
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.bottom, 10)
            }
            TradeSideSwitch(isSell: draft.isSell, choose: setSell)
                .padding(.bottom, 8)
            FormRow(label: L10n.string("Stock"), note: holdingNote) { stock }
            FormRow(label: L10n.string("How much")) { amount }
            if draft.isSell, !buyPrices.isEmpty {
                FormRow(label: L10n.string("From")) { buys }
            }
            TimelineView(.periodic(from: .now, by: 10)) { context in
                FormRow(label: L10n.string("Price"), note: noQuote) { price(now: context.date) }
            }
        }
        .onChange(of: quote) { refreshMarketPrice() }
    }

    /// The broker had no quote for the typed stock.
    @MainActor private var noQuote: String? {
        guard let quote, quote.price(isSell: draft.isSell) == nil else { return nil }
        return quote.detail(isSell: draft.isSell)
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
                FlowRow(spacing: 22, lineSpacing: 12) {
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
            .textFieldStyle(.plain)
            .font(draft.symbol.trimmed.isEmpty ? DesignTokens.bodyText : DesignTokens.bodyText.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.bottom, 5)
            .frame(width: 200)
            .focused($focusedField, equals: "symbol")
            .overlay(alignment: .bottom) { fieldLine(focusedField == "symbol" || draft.symbol.trimmed.isEmpty) }
            .accessibilityLabel(L10n.string("Symbol"))
            .accessibilityIdentifier("review.symbol")
            .onChange(of: draft.symbol) { refreshMarketPrice() }
        }
    }

    @MainActor private func detail(of held: ManualHolding) -> String {
        let shares = Humanize.shares(held.shares)
        guard let value = held.value else { return shares }
        return L10n.string("%@ · %@", shares, Humanize.usd(value))
    }

    // MARK: Amount

    @ViewBuilder private var amount: some View {
        let options = draft.isSell ? ManualInstructionDraft.sellShares : ManualInstructionDraft.buySizes
        FlowRow(spacing: 22, lineSpacing: 12) {
            ForEach(options, id: \.self) { option in
                FormChoice(title: shareTitle(option), detail: buyDetail(option), isOn: isChosen(option)) {
                    draft.fraction = option
                    draft.usdAmount = ""
                }
                .accessibilityIdentifier("review.amount.\(Humanize.fraction(option.isEmpty ? "1" : option))")
            }
            // A dollar amount the post named.
            if !draft.isSell, !draft.usdAmount.isEmpty {
                ChoiceWord(title: Humanize.dollars(draft.usdAmount), isOn: true) {}
            }
            // A size the post named that isn't one of the usual ones.
            if !draft.fraction.isEmpty, !options.contains(where: { isChosen($0) }) {
                FormChoice(title: shareTitle(draft.fraction), detail: buyDetail(draft.fraction), isOn: true) {}
            }
        }
    }

    private func isChosen(_ option: String) -> Bool {
        guard draft.isSell || draft.usdAmount.isEmpty else { return false }
        return option.isEmpty ? draft.fraction.trimmed.isEmpty : ManualInstructionDraft.sameShare(option, draft.fraction)
    }

    @MainActor private func shareTitle(_ option: String) -> String {
        if option.isEmpty { return L10n.string("Full") }
        let fraction = Humanize.fraction(option)
        if fraction == "1" { return L10n.string(draft.isSell ? "All" : "Full") }
        let glyphs = ["1/6": "⅙", "1/4": "¼", "1/3": "⅓", "1/2": "½", "2/3": "⅔", "3/4": "¾", "1/5": "⅕", "1/8": "⅛"]
        return glyphs[fraction] ?? fraction
    }

    /// What a buy of this size asks for in the one chosen account, before its limits.
    @MainActor private func buyDetail(_ option: String) -> String? {
        guard !draft.isSell, let fullPosition,
            let budget = fullPosition.copiedBudgetUSD(sourceFraction: option.isEmpty ? nil : Decimal(string: option))
        else { return nil }
        return Humanize.dollars("\(budget)")
    }

    // MARK: Buys

    private var buyPrices: [Decimal] {
        var prices = holding?.buyPrices ?? []
        if let named = Decimal(string: draft.entryPrice.trimmed), !prices.contains(named) { prices.append(named) }
        return prices
    }

    private var buys: some View {
        FlowRow(spacing: 22, lineSpacing: 12) {
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

    @ViewBuilder private func price(now: Date) -> some View {
        let post = Decimal(string: draft.postPrice.trimmed)
        let sent = Decimal(string: draft.price.trimmed)
        // A sell at the market sends no price; a buy at the market sends the last price.
        let atMarket = draft.isSell ? draft.price.trimmed.isEmpty : marketPrice != nil && sent == marketPrice && sent != post
        let atPost = post != nil && sent == post
        let other = typesPrice || (!atMarket && !atPost)
        FlowRow(spacing: 22, lineSpacing: 12) {
            if let post {
                FormChoice(title: Humanize.dollars("\(post)"), detail: L10n.string("the guru's price"), isOn: !typesPrice && atPost) {
                    typesPrice = false
                    draft.price = draft.postPrice
                }
            }
            if draft.isSell || marketPrice != nil {
                FormChoice(
                    title: L10n.string("Market"),
                    detail: marketDetail(now: now),
                    isOn: !typesPrice && atMarket
                ) {
                    typesPrice = false
                    draft.price = draft.isSell ? "" : marketPrice.map { "\($0)" } ?? ""
                }
                .accessibilityIdentifier("review.price.market")
            }
            if post != nil || draft.isSell || marketPrice != nil {
                FormChoice(title: L10n.string("Limit…"), isOn: other) {
                    typesPrice = true
                    if draft.isSell, draft.price.trimmed.isEmpty { draft.price = marketPrice.map { "\($0)" } ?? "" }
                }
            }
            if other {
                TextField(
                    L10n.string("Price"), text: $draft.price,
                    prompt: Text(L10n.string("Limit price")).foregroundStyle(Palette.tertiaryInk)
                )
                .textFieldStyle(.plain)
                .font(DesignTokens.bodyEmphasis)
                .monospacedDigit()
                .padding(.bottom, 4)
                .frame(width: 96)
                .focused($focusedField, equals: "price")
                .overlay(alignment: .bottom) { fieldLine(focusedField == "price" || draft.price.trimmed.isEmpty) }
                .accessibilityLabel(L10n.string("Price in the post"))
                .accessibilityIdentifier("review.price")
            }
        }
    }

    /// A sell at the market goes just under the live bid; a buy at the ask. The live quote says
    /// when it was quoted; a held stock's last price, until it comes, says only the price.
    @MainActor private func marketDetail(now: Date) -> String? {
        if let quote, marketPrice != nil { return quote.detail(isSell: draft.isSell, now: now) }
        guard let marketPrice else { return draft.isSell ? L10n.string("At the bid") : nil }
        return L10n.string("≈ %@", Humanize.usd(marketPrice))
    }

    /// A field's writing line: solid ink while it is being edited, dotted while it is still empty.
    private func fieldLine(_ isShown: Bool) -> some View {
        WritingLine(isActive: isShown)
    }

    // MARK: Changes

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
        refreshMarketPrice()
    }

    private func pick(_ newSymbol: String) {
        draft.symbol = newSymbol
        draft.entryPrice = ""
        refreshMarketPrice()
    }

    /// With no price in the post, a buy follows the last price of whichever stock is chosen; a
    /// sell stays at the market.
    private func refreshMarketPrice() {
        guard draft.postPrice.trimmed.isEmpty, !typesPrice else { return }
        draft.price = draft.isSell ? "" : marketPrice.map { "\($0)" } ?? ""
    }
}
