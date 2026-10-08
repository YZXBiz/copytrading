import SwiftUI

/// Reveals its content from left to right once, the way a pen draws a line, and again whenever
/// `token` changes. Under Reduce Motion it is simply there.
struct DrawInReveal: ViewModifier {
    let token: Int
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * progress)
                }
            }
            .onAppear(perform: draw)
            .onChange(of: token) { draw() }
    }

    private func draw() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        progress = 0
        withAnimation(.easeInOut(duration: 1.3)) { progress = 1 }
    }
}

extension View {
    func drawsIn(token: Int = 0) -> some View {
        modifier(DrawInReveal(token: token))
    }
}
