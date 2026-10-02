import DesktopCore
import SwiftUI

/// The pipeline internals for one post, folded away unless someone is debugging.
struct ActivityTechnicalDetails: View {
    let item: SourceActivity
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ActivityTechnicalDetailsContent(item: item)
        } label: {
            Label(L10n.string("Technical details"), systemImage: "wrench.and.screwdriver")
                .font(DesignTokens.caption.weight(.medium))
                .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityIdentifier("activity.technicalDetails")
    }
}
