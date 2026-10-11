import DesktopCore
import SwiftUI

/// An order's lifecycle as a short sequence: sent, then working, filled, or cancelled.
struct OrderSteps: View {
    let order: OrderActivity

    private var filled: Decimal { Decimal(engine: order.filledQuantity) ?? 0 }
    private var quantity: Decimal { Decimal(engine: order.quantity) ?? 0 }

    private var isFinished: Bool {
        ["filled", "canceled", "expired", "rejected", "done_for_day", "replaced", "released_unsubmitted", "aborted_before_submit"]
            .contains(order.status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            step(
                done: true, title: sentText,
                time: Humanize.date(order.createdAt))
            if filled > 0 {
                step(done: true, title: fillText, time: nil)
            }
            if !isFinished {
                step(
                    done: false,
                    title: L10n.string("Waiting at the broker (%@)", L10n.string(Humanize.code(order.status).lowercased())),
                    time: nil
                )
            } else if order.status != "filled" {
                step(done: true, title: finalText, time: nil, tone: order.status == "rejected" ? .critical : .inactive)
            }
        }
        .font(.callout)
    }

    @MainActor private var sentText: String {
        let side = L10n.string(order.side == "sell" ? "sell" : "buy")
        let quantity = quantity.formatted()
        if let limit = Decimal(engine: order.limitPrice)?.formatted(.currency(code: "USD")) {
            return L10n.string("Sent %@ %@ %@, limit %@", side, quantity, order.symbol, limit)
        }
        return L10n.string("Sent %@ %@ %@, at market", side, quantity, order.symbol)
    }

    @MainActor private var fillText: String {
        let price = Decimal(engine: order.averageFillPrice)?.formatted(.currency(code: "USD"))
        if filled == quantity {
            return price.map { L10n.string("Filled %@ at %@", filled.formatted(), $0) }
                ?? L10n.string("Filled %@", filled.formatted())
        }
        return price.map { L10n.string("Filled %@ of %@ at %@", filled.formatted(), quantity.formatted(), $0) }
            ?? L10n.string("Filled %@ of %@", filled.formatted(), quantity.formatted())
    }

    @MainActor private var finalText: String {
        switch order.status {
        case "rejected": L10n.string("Rejected by the broker")
        case "expired", "done_for_day": L10n.string("Expired unfilled")
        default: filled > 0 ? L10n.string("Rest cancelled") : L10n.string("Cancelled")
        }
    }

    private func step(done: Bool, title: String, time: Date?, tone: StatusTone = .positive) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? (tone == .positive ? "checkmark.circle.fill" : tone.symbol) : "circle.dotted")
                .foregroundStyle(done ? tone.color : .secondary)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(title)
                .monospacedDigit()
            Spacer(minLength: 8)
            if let time {
                Text(time, format: AppTime.style(.dateTime.hour().minute().second()))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
