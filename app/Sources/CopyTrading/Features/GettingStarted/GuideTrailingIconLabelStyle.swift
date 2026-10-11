import SwiftUI

/// The words, then a small symbol after them, as in "Connections →".
struct GuideTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
