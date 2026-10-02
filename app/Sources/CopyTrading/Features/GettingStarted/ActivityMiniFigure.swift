import SwiftUI

/// Activity in miniature: posts with what each account did, including one waiting for review.
struct ActivityMiniFigure: View {
    var body: some View {
        GuideFigure(
            description: L10n.string("Example of Activity: a buy that filled, and a post waiting for your review."),
            showsWindowControls: false
        ) {
            VStack(spacing: 6) {
                GuideActivityLine(
                    author: "Alex Chen", time: "9:41", text: "ALERT: Bought NVDA 1/6 at 121.38", outcome: "Filled",
                    tone: .positive)
                GuideActivityLine(
                    author: "Sam Lee", time: "9:58", text: "trimming some AMD here", outcome: "Needs review", tone: .caution)
            }
        }
    }
}
