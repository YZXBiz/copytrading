import SwiftUI

/// A small frosted pill at the foot of Connections while the tour runs: the setup's steps, with
/// the done ones ticked and the current one in ink.
struct SetupTourStrip: View {
    let current: SetupStep
    let progress: SetupProgress

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.string("Setup tour"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)
            ForEach(SetupStep.allCases) { step in
                if step != SetupStep.allCases.first {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk.opacity(0.6))
                }
                HStack(spacing: 3) {
                    if progress.isDone(step) && step != current {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }
                    Text(L10n.string(step.shortTitle))
                        .font(.system(size: 12, weight: step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? Palette.accent : Palette.tertiaryInk)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tour.strip")
    }
}
