import SwiftUI

/// One screen of the app in the guide: what it answers, a small live picture of it, and a way to
/// go there.
struct GuideScreenRow<Figure: View>: View {
    let screen: AppModel.Screen
    let text: String
    let open: () -> Void
    @ViewBuilder let figure: Figure

    var body: some View {
        // The guide's page keeps at least 300 points beside a figure, even at the smallest window.
        HStack(alignment: .top, spacing: 24) {
            GuideScreenDescription(screen: screen, text: text, open: open)
                .frame(maxWidth: .infinity, alignment: .leading)
            figure
                .frame(width: 250)
        }
    }
}
