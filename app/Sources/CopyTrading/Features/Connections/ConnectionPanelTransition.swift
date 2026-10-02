import SwiftUI

/// Opens a Connections panel out of the card it came from and folds it back in on close. Without a
/// card to grow from, or under Reduce Motion, it fades.
/// The shadow is drawn here, outside the growing edge, so the clip never cuts it off.
struct ConnectionPanelTransition: Transition {
    let origin: CGRect?
    let layer: CGSize
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        Group {
            if let origin, !reduceMotion {
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                    .clipShape(ConnectionMorphShape(origin: origin, layer: layer, progress: phase.isIdentity ? 1 : 0))
            } else {
                content.opacity(phase.isIdentity ? 1 : 0)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(phase.isIdentity ? 0.16 : 0), radius: 34, y: 16)
    }
}
