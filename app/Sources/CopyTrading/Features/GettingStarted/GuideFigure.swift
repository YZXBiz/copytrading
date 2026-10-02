import SwiftUI

/// A miniature CopyTrading window inside the guide, so the guide shows the app it describes.
/// It is drawn with the app's real parts rather than a screenshot, so it
/// follows light and dark appearance and never goes out of date.
struct GuideFigure<Content: View>: View {
    /// What the figure shows, for VoiceOver, which reads it as one picture.
    let description: String
    /// The window's three buttons, for the figures that stand for a whole window.
    var showsWindowControls = true
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            if showsWindowControls {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                    Spacer()
                }
                .frame(height: 8)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            content
                .padding([.horizontal, .bottom], 16)
                .padding(.top, showsWindowControls ? 2 : 16)
                .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(contrast == .increased ? Palette.secondaryInk : Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityAddTraits(.isImage)
    }
}
