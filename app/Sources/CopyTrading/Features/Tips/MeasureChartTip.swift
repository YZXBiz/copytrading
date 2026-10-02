import SwiftUI
import TipKit

/// Shown once, after a few looks at Today: dragging across the chart measures a move.
struct MeasureChartTip: Tip {
    static let chartViewed = Tips.Event(id: "chartViewed")

    let generation: Int
    let title: Text
    let message: Text?

    var id: String { "measure-chart-\(generation)" }

    @MainActor
    init(generation: Int) {
        self.generation = generation
        title = Text(L10n.string("Measure a move"))
        message = Text(L10n.string("Drag across the chart to see the change between two times. Click or press Esc to clear it."))
    }

    var image: Image? { Image(systemName: "arrow.left.and.right") }

    var rules: [Rule] {
        #Rule(Self.chartViewed) { $0.donations.count >= 3 }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}
