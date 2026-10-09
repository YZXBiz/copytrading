import SwiftUI

/// A butter-yellow marker stroke behind the lower half of some text, swept in from the left the
/// way a hand highlights a line, and wiped back out when it goes. It never repeats on its own.
struct MarkerHighlight: ViewModifier {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// In the dark the marker is softer, so light text over it stays readable.
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Palette.butter.opacity(colorScheme == .dark ? 0.4 : 0.85))
                        .frame(width: proxy.size.width + 6, height: proxy.size.height * 0.42)
                        .offset(x: -3, y: proxy.size.height * 0.52)
                        .scaleEffect(x: isOn ? 1 : 0, anchor: .leading)
                }
                .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isOn)
    }
}

extension View {
    func markerHighlight(_ isOn: Bool) -> some View {
        modifier(MarkerHighlight(isOn: isOn))
    }
}
