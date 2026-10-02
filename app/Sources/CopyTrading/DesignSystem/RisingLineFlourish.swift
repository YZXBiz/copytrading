import SwiftUI

/// The icon's line as decoration: blue turning teal, a soft glow, and the white dot on its tip. It
/// draws itself in once when it appears; Reduce Motion shows it drawn, and Reduce Transparency or
/// increased contrast leave it out.
struct RisingLineFlourish: View {
    var lineWidth: CGFloat = 2.5
    @State private var isDrawn = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { colorScheme == .dark }

    private var colors: [Color] {
        dark
            ? [Color(red: 0.3, green: 0.62, blue: 0.98), Color(red: 0.25, green: 0.88, blue: 0.7)]
            : [Color(red: 0.25, green: 0.55, blue: 0.9), Color(red: 0.11, green: 0.66, blue: 0.53)]
    }

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            GeometryReader { geometry in
                let tip = CGPoint(x: RisingLine.tip.x * geometry.size.width, y: RisingLine.tip.y * geometry.size.height)
                ZStack(alignment: .topLeading) {
                    RisingLine()
                        .trim(from: 0, to: isDrawn ? 1 : 0)
                        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth * 5, lineCap: .round, lineJoin: .round))
                        .blur(radius: lineWidth * 4)
                        .opacity(dark ? 0.24 : 0.16)
                    RisingLine()
                        .trim(from: 0, to: isDrawn ? 1 : 0)
                        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .opacity(dark ? 0.6 : 0.45)
                    Circle()
                        .fill(.white)
                        .frame(width: lineWidth * 3.6, height: lineWidth * 3.6)
                        .background(Circle().fill(colors[1].opacity(0.25)).frame(width: lineWidth * 8.8, height: lineWidth * 8.8))
                        .scaleEffect(isDrawn ? 1 : 0.2)
                        .opacity(isDrawn ? 0.9 : 0)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.5).delay(1.4), value: isDrawn)
                        .position(tip)
                }
            }
            .onAppear(perform: draw)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw() {
        guard !isDrawn else { return }
        if reduceMotion {
            isDrawn = true
        } else {
            withAnimation(.easeOut(duration: 1.6).delay(0.15)) {
                isDrawn = true
            }
        }
    }
}
