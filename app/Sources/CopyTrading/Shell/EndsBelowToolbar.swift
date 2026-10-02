import SwiftUI

extension View {
    /// Keeps a screen out of the clear toolbar strip, so pages end beneath the toolbar rather
    /// than scrolling up behind the controls.
    func endsBelowToolbar() -> some View {
        scrollEdgeEffectHidden(true, for: .top)
            .mask {
                GeometryReader { proxy in
                    Rectangle()
                        .padding(.top, proxy.safeAreaInsets.top)
                        .ignoresSafeArea()
                }
            }
    }
}
