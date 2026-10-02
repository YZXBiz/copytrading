import SwiftUI

/// A guru's recent posts as a row of small beads, oldest at the left: green for a call that was
/// copied, orange for one waiting on review, grey for chatter. Decorative; the card says the same
/// in words.
struct GuruCallTrail: View {
    let trail: [StatusTone]
    /// Empty places drawn as faint rings, so a new guru's trail reads as waiting rather than missing.
    var places = 12

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<places, id: \.self) { index in
                let offset = index - (places - trail.count)
                if offset >= 0 {
                    Circle()
                        .fill(color(trail[offset]))
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .strokeBorder(Palette.secondaryInk.opacity(0.25), lineWidth: 1)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ tone: StatusTone) -> Color {
        switch tone {
        case .inactive: Palette.secondaryInk.opacity(0.35)
        default: tone.color
        }
    }
}
