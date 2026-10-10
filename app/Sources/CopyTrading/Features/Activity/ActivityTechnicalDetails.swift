import DesktopCore
import SwiftUI

/// The pipeline internals for one post, folded away under a tracked-capital label unless someone
/// is debugging.
struct ActivityTechnicalDetails: View {
    let item: SourceActivity
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ActivityLabel(text: L10n.string("Technical details"), color: Palette.secondaryInk)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(QuietPressButtonStyle())
            .accessibilityValue(L10n.string(isExpanded ? "Expanded" : "Collapsed"))
            .accessibilityIdentifier("activity.technicalDetails")
            if isExpanded {
                ActivityTechnicalDetailsContent(item: item)
                    .padding(.top, 20)
            }
        }
    }
}
