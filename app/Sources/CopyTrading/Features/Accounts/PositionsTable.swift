import DesktopCore
import SwiftUI

/// Shares per symbol: what CopyTrading bought, what the owner holds outside it, and the broker's
/// total. A position opens into its lots, each with the post that bought it.
struct PositionsTable: View {
    let positions: [AccountPositionView]
    let accountID: String
    let environment: TradingEnvironment
    let gurus: GuruDirectory
    /// Loaded Activity, where a lot's post can be opened.
    let activity: [SourceActivity]
    let openPost: (SourceActivity) -> Void
    let saleOperations: (any LotSaleOperations)?
    let confirmOwner: (String) async throws -> Void
    let saleFinished: () -> Void
    @State private var expanded: Set<String> = []
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
                Divider()
                ForEach(positions) { position in
                    PositionRow(
                        position: position,
                        isExpanded: expanded.contains(position.id),
                        toggle: { toggle(position) }
                    )
                    if expanded.contains(position.id) {
                        VStack(spacing: 0) {
                            ForEach(position.lots) { lot in
                                Divider()
                                let guruName = gurus.gurus.first { $0.id == lot.guruID }?.name ?? lot.guruID.map(Humanize.code)
                                PositionLotRow(
                                    lot: lot,
                                    guruName: guruName,
                                    post: lot.sourceID.flatMap { id in activity.first { $0.sourceID == id } },
                                    openPost: openPost,
                                    sell: {
                                        selling = LotSaleTarget(
                                            accountID: accountID, environment: environment, symbol: position.symbol, lot: lot,
                                            guruName: guruName)
                                    }
                                )
                            }
                        }
                        .padding(.leading, PositionRow.lotInset)
                        .transition(.opacity)
                    }
                    if position.id != positions.last?.id {
                        Divider()
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
            ForEach(["Copied", "Held outside CopyTrading", "At broker"], id: \.self) { title in
                Text(L10n.string(title))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.tertiaryInk)
        .padding(.vertical, 6)
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
