import SwiftUI

/// A caution line: an orange circled mark before quiet words.
struct GuideCautionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}
