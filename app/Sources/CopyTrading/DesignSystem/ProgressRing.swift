import SwiftUI

/// Progress as a ring: a quiet track and
/// an accent arc that grows, closing into a green ring with a check drawn in once everything is.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 28
    var lineWidth: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(1, max(0, progress)) }
    private var isComplete: Bool { clamped >= 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(isComplete ? Color.green : Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: clamped)
        .accessibilityElement()
        .accessibilityLabel(L10n.string("Setup progress"))
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}
