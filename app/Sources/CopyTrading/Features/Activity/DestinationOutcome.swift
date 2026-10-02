import DesktopCore
import SwiftUI

/// What one account did with one post, in the order a trader cares about.
enum DestinationOutcome: Equatable {
    case filled(String)
    case partlyFilled(String)
    case working(String)
    case cancelled(String)
    case failed(String)
    case skipped(String)
    case processedWithoutOrder
    case waiting
    case needsReview(String)

    @MainActor
    init(_ destination: DestinationActivity) {
        if let order = destination.orders.first {
            self = Self.order(order, count: destination.orders.count)
            return
        }
        if destination.status == "review_required" {
            self = .needsReview(L10n.string(Reason.text(destination.status)))
        } else if ["stale", "out_of_order", "ignored"].contains(destination.status) {
            self = .skipped(L10n.string(Reason.text(destination.status)))
        } else if destination.status == "done" {
            self = .processedWithoutOrder
        } else {
            self = .waiting
        }
    }

    @MainActor
    private static func order(_ order: OrderActivity, count: Int) -> Self {
        let verb = L10n.string(order.side == "sell" ? "Sold" : "Bought")
        let filled = Decimal(engine: order.filledQuantity) ?? 0
        let quantity = Decimal(engine: order.quantity) ?? 0
        let price = Decimal(engine: order.averageFillPrice)?.formatted(.currency(code: "USD"))
        switch order.status {
        case "filled":
            var detail = L10n.string("%@ %@ %@", verb, filled.formatted(), order.symbol)
            if let price { detail = L10n.string("%@ at %@", detail, price) }
            if count > 1 { detail = L10n.string("%@ and %lld more", detail, Int64(count - 1)) }
            return .filled(detail)
        case "partially_filled":
            var detail = L10n.string("%@ %@ of %@ %@", verb, filled.formatted(), quantity.formatted(), order.symbol)
            if let price { detail = L10n.string("%@ at %@", detail, price) }
            return .partlyFilled(detail)
        case "canceled", "expired", "done_for_day", "replaced", "released_unsubmitted", "aborted_before_submit":
            if filled > 0 {
                var detail = L10n.string("%@ %@ of %@ %@", verb, filled.formatted(), quantity.formatted(), order.symbol)
                if let price { detail = L10n.string("%@ at %@", detail, price) }
                return .partlyFilled(L10n.string("%@, rest cancelled", detail))
            }
            return .cancelled(L10n.string("Order for %@ %@ was cancelled", quantity.formatted(), order.symbol))
        case "rejected":
            return .failed(L10n.string("The broker rejected the order for %@", order.symbol))
        case "uncertain", "unrecognized":
            return .needsReview(L10n.string("The broker has not confirmed the order for %@", order.symbol))
        default:
            let side = L10n.string(order.side == "sell" ? "Selling" : "Buying")
            var detail = L10n.string("%@ %@ %@", side, quantity.formatted(), order.symbol)
            if let limit = Decimal(engine: order.limitPrice)?.formatted(.currency(code: "USD")) {
                detail = L10n.string("%@ at up to %@", detail, limit)
            }
            return .working(detail)
        }
    }

    @MainActor var title: String {
        switch self {
        case .filled: L10n.string("Filled")
        case .partlyFilled: L10n.string("Partly filled")
        case .working: L10n.string("Working")
        case .cancelled: L10n.string("Cancelled")
        case .failed: L10n.string("Failed")
        case .skipped: L10n.string("Skipped")
        case .processedWithoutOrder: L10n.string("Processed")
        case .waiting: L10n.string("Waiting")
        case .needsReview: L10n.string("Needs review")
        }
    }

    @MainActor var detail: String {
        switch self {
        case .filled(let text), .partlyFilled(let text), .working(let text), .cancelled(let text),
            .failed(let text), .skipped(let text), .needsReview(let text):
            text
        case .processedWithoutOrder:
            L10n.string("Processing finished without an order.")
        case .waiting:
            L10n.string("Waiting to be sized and sent")
        }
    }

    var tone: StatusTone {
        switch self {
        case .filled: .positive
        case .partlyFilled, .working, .processedWithoutOrder, .waiting: .neutral
        case .cancelled, .skipped: .inactive
        case .failed: .critical
        case .needsReview: .caution
        }
    }

    var symbol: String {
        switch self {
        case .filled: "checkmark.circle.fill"
        case .partlyFilled: "circle.lefthalf.filled"
        case .working, .waiting: "clock"
        case .processedWithoutOrder: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .failed: "xmark.octagon.fill"
        case .skipped: "minus.circle"
        case .needsReview: "exclamationmark.bubble.fill"
        }
    }
}

struct DestinationInstructionDetail: Equatable, Identifiable {
    let offset: Int
    let value: String

    var id: Int { offset }
}

enum DestinationInstructionDetails {
    @MainActor static var title: String { L10n.string("Instruction details") }

    @MainActor static func rows(
        for destination: DestinationActivity,
        summary: DestinationOutcome
    ) -> [DestinationInstructionDetail] {
        let details = destination.instructionOutcomes.enumerated().map { offset, code in
            DestinationInstructionDetail(offset: offset, value: L10n.string(Reason.text(code)))
        }
        guard destination.orders.isEmpty,
            details.count == 1,
            details[0].value == summary.detail
        else {
            return details
        }
        return []
    }
}
