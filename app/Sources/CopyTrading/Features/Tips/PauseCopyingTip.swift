import SwiftUI
import TipKit

/// Shown once, the first time copying runs: the one switch that stops everything.
struct PauseCopyingTip: Tip {
    static let copyingStarted = Tips.Event(id: "copyingStarted")

    let generation: Int
    let title: Text
    let message: Text?

    var id: String { "pause-copying-\(generation)" }

    @MainActor
    init(generation: Int) {
        self.generation = generation
        title = Text(L10n.string("Stop from anywhere"))
        message = Text(
            L10n.string(
                "Stop Copying stops reading new posts and placing orders for every account. Each account's Start Copying picks up again."))
    }

    var image: Image? { Image(systemName: "stop.circle") }

    var rules: [Rule] {
        #Rule(Self.copyingStarted) { $0.donations.count >= 1 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}
