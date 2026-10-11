import SwiftUI

/// A caution line: a grey circled mark before quiet words.
struct GuideCautionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}
