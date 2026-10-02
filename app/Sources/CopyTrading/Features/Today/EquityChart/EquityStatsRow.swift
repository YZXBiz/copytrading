import DesktopCore
import SwiftUI

/// The window at a glance under the curve: where it started, its extremes, and its worst fall.
struct EquityStatsRow: View {
    let stats: EquityCurveStats?
    let hasPreviousClose: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 32) { items }
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                GridRow {
                    item("\(startLabel)", stats.map { money($0.reference) })
                    item("High", stats.map { money($0.high.value) })
                }
                GridRow {
                    item("Low", stats.map { money($0.low.value) })
                    drawdown
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1).accessibilityHidden(true)
        }
    }

    private var startLabel: String { hasPreviousClose ? "Previous close" : "Start" }

    @ViewBuilder
    private var items: some View {
        item(startLabel, stats.map { money($0.reference) })
        item("High", stats.map { money($0.high.value) })
        item("Low", stats.map { money($0.low.value) })
        drawdown
    }

    private var drawdown: some View {
        item(
            "Largest drop",
            stats.map { stats in
                stats.maxDrawdown == 0
                    ? "None"
                    : "−\(money(stats.maxDrawdown)) (−\(stats.maxDrawdownFraction.formatted(.percent.precision(.fractionLength(2)))))"
            }
        )
        .help(L10n.string("The biggest fall from a high to a later low in this window."))
    }

    private func item(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string(label))
                .font(DesignTokens.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(DesignTokens.bodyText)
                .monospacedDigit()
                .foregroundStyle(value == nil ? Palette.tertiaryInk : Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
