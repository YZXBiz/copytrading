import SwiftUI
import TipKit

/// Shown once, the first time a post waits for the owner: where those posts collect.
struct NeedsReviewTip: Tip {
    static let reviewWaiting = Tips.Event(id: "reviewWaiting")

    let generation: Int
    let title: Text
    let message: Text?

    var id: String { "needs-review-\(generation)" }

    @MainActor
    init(generation: Int) {
        self.generation = generation
        title = Text(L10n.string("A call is waiting for you"))
        message = Text(
            L10n.string(
                "Some posts need you: a suggestion, an “if”, or a price that has moved. They wait here until you copy or skip them."
            ))
    }

    var image: Image? { Image(systemName: "exclamationmark.bubble") }

    var rules: [Rule] {
        #Rule(Self.reviewWaiting) { $0.donations.count >= 1 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}
