import SwiftUI

/// How a post becomes a trade: the journey drawn as one path whose stops are buttons, and one card
/// under it for the chosen stop, so the page shows two lines at a time instead of six paragraphs.
struct GuideJourneySection: View {
    let open: (AppModel.Screen) -> Void
    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GuideJourneyDiagram(selection: $selection)
            GuideJourneyCard(index: selection, open: open, select: { selection = $0 })
        }
    }
}
