import DesktopCore
import SwiftUI

/// Positions the way a trader reads them: shares, average cost, current price, value, and gain or
/// loss, from the broker's valuation. A position opens into its lots, each with the post that
/// bought it and its own gain or loss.
struct PositionsTable: View {
    let allPositions: [AccountPositionView]
    let accountID: String
    let environment: TradingEnvironment
    let approvesOrders: Bool
    let gurus: GuruDirectory
    /// Loaded Activity, where a lot's post can be opened.
    let activity: [SourceActivity]
    let openPost: (SourceActivity) -> Void
    let saleOperations: (any LotSaleOperations)?
    let confirmOwner: (String) async throws -> Void
    let saleFinished: () -> Void
    @State private var expanded: Set<String> = []

    init(
        positions: [AccountPositionView], accountID: String, environment: TradingEnvironment, approvesOrders: Bool,
        gurus: GuruDirectory, activity: [SourceActivity], openPost: @escaping (SourceActivity) -> Void,
        saleOperations: (any LotSaleOperations)?, confirmOwner: @escaping (String) async throws -> Void,
        saleFinished: @escaping () -> Void
    ) {
        self.allPositions = positions
        self.accountID = accountID
        self.environment = environment
        self.approvesOrders = approvesOrders
        self.gurus = gurus
        self.activity = activity
        self.openPost = openPost
        self.saleOperations = saleOperations
        self.confirmOwner = confirmOwner
        self.saleFinished = saleFinished
    }

    /// Positions with something in them; an emptied symbol has nothing to read.
    private var positions: [AccountPositionView] { allPositions.filter { !PositionRow.isEmpty($0) } }
    @State private var selling: LotSaleTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if positions.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(L10n.string("No open positions. Copied buys appear here, next to anything you hold outside CopyTrading."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                header
                Hairline()
                ForEach(positions) { position in
                    PositionRow(
                        position: position,
                        isExpanded: expanded.contains(position.id),
                        toggle: { toggle(position) }
                    )
                    if expanded.contains(position.id) {
                        VStack(spacing: 0) {
                            ForEach(position.lots) { lot in
                                Hairline()
                                let guruName = gurus.gurus.first { $0.id == lot.guruID }?.name ?? lot.guruID.map(Humanize.code)
                                PositionLotRow(
                                    lot: lot,
                                    guruName: guruName,
                                    post: lot.sourceID.flatMap { id in activity.first { $0.sourceID == id } },
                                    openPost: openPost,
                                    sell: {
                                        selling = LotSaleTarget(
                                            accountID: accountID, environment: environment, symbol: position.symbol, lot: lot,
                                            guruName: guruName, approvesOrders: approvesOrders)
                                    }
                                )
                            }
                        }
                        .padding(.leading, PositionRow.lotInset)
                        .transition(.opacity)
                    }
                    if position.id != positions.last?.id {
                        Hairline()
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: expanded)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.string("Positions"))
            .sheet(item: $selling) { target in
                LotSaleSheet(
                    target: target,
                    operations: saleOperations,
                    confirmOwner: { try await confirmOwner("Sell \(target.symbol) from \(target.accountID)") },
                    finished: saleFinished
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(L10n.string("Symbol"))
                .padding(.leading, PositionRow.lotInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["Shares", "Avg cost", "Price", "Value", "Gain/loss"], id: \.self) { title in
                Text(L10n.string(title))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(DesignTokens.caption.weight(.medium))
        .foregroundStyle(Palette.tertiaryInk)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func toggle(_ position: AccountPositionView) {
        if expanded.contains(position.id) {
            expanded.remove(position.id)
        } else {
            expanded.insert(position.id)
        }
    }
}
