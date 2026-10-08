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
            // Say why it waits ("The post repeats an earlier call of the guru's"), not that it waits.
            let why = destination.instructionOutcomes.first { $0 != "review_required" && $0 != "pending" }
            self = .needsReview(Reason.text(why ?? destination.status))
        } else if ["stale", "out_of_order", "ignored"].contains(destination.status) {
            self = .skipped(Reason.text(destination.status))
        } else if destination.status == "done" {
            self = .processedWithoutOrder
        } else {
            self = .waiting
        }
    }

    /// One order in a phrase, dollar first: "Bought $199.82 of PM", "Order for $200 of PM was
    /// cancelled". Share counts stay with the order's facts.
    @MainActor
    static func order(_ order: OrderActivity, count: Int) -> Self {
        let selling = order.side == "sell"
        let filled = Decimal(engine: order.filledQuantity) ?? 0
        let planned = OrderAmount.planned(order) ?? order.symbol
        let done = OrderAmount.filled(order) ?? planned
        switch order.status {
        case "filled":
            var detail = L10n.string(selling ? "Sold %@" : "Bought %@", done)
            if count > 1 { detail = L10n.string("%@ and %lld more", detail, Int64(count - 1)) }
            return .filled(detail)
        case "partially_filled":
            return .partlyFilled(L10n.string(selling ? "Partly sold: %@ so far" : "Partly bought: %@ so far", done))
        case "canceled", "expired", "done_for_day", "replaced", "released_unsubmitted", "aborted_before_submit":
            if filled > 0 {
                return .partlyFilled(L10n.string(selling ? "Sold %@, rest cancelled" : "Bought %@, rest cancelled", done))
            }
            return .cancelled(L10n.string("Order for %@ was cancelled", planned))
        case "rejected":
            return .failed(L10n.string("The broker rejected the order for %@", order.symbol))
        case "uncertain", "unrecognized":
            return .needsReview(L10n.string("The broker has not confirmed the order for %@", order.symbol))
        default:
            var detail = L10n.string(selling ? "Selling %@" : "Buying %@", planned)
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
            DestinationInstructionDetail(offset: offset, value: Reason.text(code))
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
