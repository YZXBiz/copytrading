import DesktopCore
import SwiftUI

/// The first thing after a long while away: how each account moved, what filled, and what waits,
/// as one calm sheet that closes with one button. Each fill reads as a sentence with whose post it
/// came from; money moves carry their own arrow and colour.
struct RecapSheet: View {
    let recap: Recap
    let directory: GuruDirectory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            kind: L10n.string("While you were away"),
            title: L10n.string("Here's what happened"),
            lede: L10n.string("Since %@", recap.since.formatted(AppTime.style(.dateTime.weekday(.abbreviated).hour().minute())))
        ) {
            if !recap.moves.isEmpty {
                SheetSection(L10n.string("Accounts")) {
                    ForEach(recap.moves, id: \.accountID) { move in
                        SheetRow(title: move.accountID) {
                            change(move.change)
                        }
                    }
                }
            }
            SheetSection(L10n.string("Filled")) {
                if recap.fills.isEmpty {
                    Text(L10n.string("Nothing filled while you were away."))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.vertical, 8)
                } else {
                    ForEach(recap.fills, id: \.clientID) { fill in
                        fillRow(fill)
                    }
                }
            }
            if recap.waiting > 0 {
                AttentionRow(
                    headline: recap.waiting == 1
                        ? L10n.string("One call is waiting for you")
                        : L10n.string("%lld calls are waiting for you", Int64(recap.waiting)),
                    detail: L10n.string("They're at the top of each account's page.")
                ) {
                    EmptyView()
                }
            }
        } actions: {
            Button(L10n.string("Done"), action: dismiss.callAsFunction)
                .buttonStyle(SheetButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 560)
    }

    private func change(_ value: Decimal) -> some View {
        let direction = ChangeDirection(value)
        return Label {
            Text(value.magnitude.formatted(.currency(code: "USD")))
                .monospacedDigit()
        } icon: {
            Image(systemName: direction.symbol)
        }
        .font(DesignTokens.statValue)
        .foregroundStyle(direction.color)
        .accessibilityLabel(direction.spoken(value))
    }

    private func fillRow(_ fill: FillWatch.Fill) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            OutcomeMark(tone: .positive, size: 12)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 3) {
                Text(sentence(fill))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                Text(
                    directory.name(for: fill.guruID).map { L10n.string("From %@'s post · %@", $0, fill.accountID) }
                        ?? L10n.string("Into %@", fill.accountID)
                )
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func sentence(_ fill: FillWatch.Fill) -> String {
        let shares = Humanize.shares(fill.shares)
        guard let price = fill.price else {
            return fill.side == "sell"
                ? L10n.string("Sold %@ of %@", shares, fill.symbol) : L10n.string("Bought %@ of %@", shares, fill.symbol)
        }
        let at = price.formatted(.currency(code: "USD"))
        return fill.side == "sell"
            ? L10n.string("Sold %@ of %@ at %@", shares, fill.symbol, at)
            : L10n.string("Bought %@ of %@ at %@", shares, fill.symbol, at)
    }
}
