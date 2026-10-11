import DesktopCore
import SwiftUI

/// What should happen, as plain choices: buy or sell, the stock (for a sell, one CopyTrading
/// holds), how much, which buys a sell takes from, and the price.
struct ManualInstructionEditor: View {
    @Binding var draft: ManualInstructionDraft
    /// What CopyTrading holds in the chosen accounts.
    let holdings: [ManualHolding]
    /// The last price of every stock any account holds, by symbol.
    let marketPrices: [String: Decimal]
    /// A full position for this guru in the one chosen account; nil when several are chosen.
    let fullPosition: TradingRouteConnection?
    /// "Trade 2 of 3" with Remove, when the sheet holds more than one.
    let position: (index: Int, count: Int)?
    let remove: () -> Void
    @State private var typesPrice = false
    @FocusState private var focusedField: String?

    private var symbol: String { draft.symbol.trimmed.uppercased() }
    private var holding: ManualHolding? { holdings.first { $0.symbol == symbol } }
    private var marketPrice: Decimal? { holding?.price ?? marketPrices[symbol] }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let position {
                HStack {
                    Eyebrow(L10n.string("Trade %lld of %lld", Int64(position.index + 1), Int64(position.count)))
                    Spacer()
                    Button(L10n.string("Remove"), action: remove)
                        .buttonStyle(QuietPressButtonStyle())
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 30) {
                ChoiceWord(title: L10n.string("Buy"), large: true, isOn: !draft.isSell) { setSell(false) }
                    .accessibilityIdentifier("review.buy")
                ChoiceWord(title: L10n.string("Sell"), large: true, isOn: draft.isSell) { setSell(true) }
                    .accessibilityIdentifier("review.sell")
            }
            choice(L10n.string("Stock")) { stock }
            choice(L10n.string(draft.isSell ? "How much to sell" : "How much to buy")) { amount }
            if draft.isSell, !buyPrices.isEmpty {
                choice(L10n.string("From")) { buys }
            }
            choice(L10n.string("Order price")) { price }
        }
    }

    private func choice(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(label)
            content()
        }
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
                FlowRow(spacing: 26, lineSpacing: 14) {
                    ForEach(holdings) { held in
                        ChoiceWord(title: held.symbol, detail: detail(of: held), isOn: held.symbol == symbol) {
                            pick(held.symbol)
                        }
                        .accessibilityIdentifier("review.stock.\(held.symbol)")
                    }
                    if named {
                        ChoiceWord(title: symbol, detail: L10n.string("Not held"), isOn: true) {}
                    }
                }
            }
        } else {
            TextField(L10n.string("Ticker"), text: $draft.symbol, prompt: Text(L10n.string("Ticker")).foregroundStyle(Palette.tertiaryInk))
                .textFieldStyle(.plain)
                .font(DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 6)
                .frame(width: 170)
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
        FlowRow(spacing: 26, lineSpacing: 14) {
            ForEach(options, id: \.self) { option in
                ChoiceWord(title: shareTitle(option), detail: buyDetail(option), isOn: isChosen(option)) {
                    draft.fraction = option
                }
                .accessibilityIdentifier("review.amount.\(Humanize.fraction(option.isEmpty ? "1" : option))")
            }
            // A size the post named that isn't one of the usual ones.
            if !draft.fraction.isEmpty, !options.contains(where: { isChosen($0) }) {
                ChoiceWord(title: shareTitle(draft.fraction), detail: buyDetail(draft.fraction), isOn: true) {}
            }
        }
    }

    private func isChosen(_ option: String) -> Bool {
        option.isEmpty ? draft.fraction.trimmed.isEmpty : ManualInstructionDraft.sameShare(option, draft.fraction)
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
        FlowRow(spacing: 26, lineSpacing: 14) {
            ChoiceWord(title: L10n.string("Every buy"), isOn: draft.entryPrice.trimmed.isEmpty) { draft.entryPrice = "" }
            ForEach(buyPrices, id: \.self) { price in
                ChoiceWord(
                    title: L10n.string("The buy at %@", Humanize.dollars("\(price)")),
                    isOn: Decimal(string: draft.entryPrice.trimmed) == price
                ) { draft.entryPrice = "\(price)" }
            }
        }
    }

    // MARK: Price

    @ViewBuilder private var price: some View {
        let post = Decimal(string: draft.postPrice.trimmed)
        let sent = Decimal(string: draft.price.trimmed)
        // A sell at the market sends no price; a buy at the market sends the last price.
        let atMarket = draft.isSell ? draft.price.trimmed.isEmpty : marketPrice != nil && sent == marketPrice && sent != post
        let atPost = post != nil && sent == post
        let other = typesPrice || (!atMarket && !atPost)
        FlowRow(spacing: 26, lineSpacing: 14) {
            if let post {
                ChoiceWord(title: Humanize.dollars("\(post)"), detail: L10n.string("The guru's price"), isOn: !typesPrice && atPost) {
                    typesPrice = false
                    draft.price = draft.postPrice
                }
            }
            if draft.isSell || marketPrice != nil {
                ChoiceWord(
                    title: L10n.string("Market"),
                    detail: marketDetail,
                    isOn: !typesPrice && atMarket
                ) {
                    typesPrice = false
                    draft.price = draft.isSell ? "" : marketPrice.map { "\($0)" } ?? ""
                }
                .accessibilityIdentifier("review.price.market")
            }
            if post != nil || draft.isSell || marketPrice != nil {
                ChoiceWord(title: L10n.string("Other"), isOn: other) {
                    typesPrice = true
                    if draft.isSell, draft.price.trimmed.isEmpty { draft.price = marketPrice.map { "\($0)" } ?? "" }
                }
            }
            if other {
                TextField(L10n.string("Price"), text: $draft.price, prompt: Text(L10n.string("Price")).foregroundStyle(Palette.tertiaryInk))
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

    /// A sell at the market goes just under the live bid; a buy at the last price.
    @MainActor private var marketDetail: String? {
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
        draft.exitBasis = nil
        if sell {
            if holding == nil, let first = holdings.first { pick(first.symbol) }
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
