import SwiftUI

/// The small ink mark in front of an outcome sentence, so how a thing ended reads before its words:
/// a solid ink disc with a tick when it went through, the butter bead while it is still going, an
/// amber ring while it waits on the owner, and a hollow ring when it did not happen (a dash) or
/// failed (a cross). Each has its own shape, so the mark never depends on colour alone.
struct OutcomeMark: View {
    let tone: StatusTone
    var size: CGFloat = 15

    var body: some View {
        mark
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch tone {
        case .positive:
            Circle()
                .fill(Palette.ink)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .heavy))
                        .foregroundStyle(Palette.page)
                }
        case .neutral:
            InkBead()
        case .caution:
            Circle()
                .strokeBorder(Palette.amber, lineWidth: InkStroke.width)
                .overlay(Circle().fill(Palette.amber).frame(width: size * 0.3, height: size * 0.3))
        case .critical:
            Circle()
                .strokeBorder(Palette.ink, lineWidth: InkStroke.width)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
        case .inactive:
            Circle()
                .strokeBorder(Palette.ink, lineWidth: InkStroke.width)
                .overlay(Capsule().fill(Palette.ink).frame(width: size * 0.42, height: InkStroke.width))
        }
    }
}
