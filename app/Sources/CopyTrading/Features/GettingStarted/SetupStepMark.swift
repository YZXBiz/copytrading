import SwiftUI

/// A checklist step's mark: an empty ring while it waits, a green check drawn in once it is done.
struct SetupStepMark: View {
    let isDone: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.tertiaryInk.opacity(isDone ? 0 : 0.55), lineWidth: 1.5)
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .frame(width: 22, height: 22)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: isDone)
        .accessibilityHidden(true)
    }
}
