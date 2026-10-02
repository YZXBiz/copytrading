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
        title = Text(L10n.string("A post needs you"))
        message = Text(
            L10n.string("When CopyTrading can't read a post with confidence, it trades nothing and waits here for you to review it."))
    }

    var image: Image? { Image(systemName: "exclamationmark.bubble") }

    var rules: [Rule] {
        #Rule(Self.reviewWaiting) { $0.donations.count >= 1 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}
