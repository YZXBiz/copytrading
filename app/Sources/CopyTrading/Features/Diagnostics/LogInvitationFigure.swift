import SwiftUI

/// What the log will hold, drawn on a slip of paper: records in time order with a dot for how
/// each ended, and one opened to its details. Shapes only, no made-up records.
struct LogInvitationFigure: View {
    var body: some View {
        ZStack {
            PaperSlip(tilt: -2.5) {
                VStack(alignment: .leading, spacing: 8) {
                    record(.green, [70, 44])
                    record(.green, [58, 66])
                    record(.orange, [82, 38])
                    record(.green, [50, 60])
                }
            }
            .offset(x: -78, y: 0)
            PaperSlip(tilt: 3) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        SketchBar(width: 64, strength: 0.22)
                    }
                    ForEach([110, 90, 120, 74], id: \.self) { width in
                        SketchBar(width: CGFloat(width), height: 5, strength: 0.08)
                    }
                    Text(L10n.string("Keys removed"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.ink.opacity(0.06), in: .capsule)
                }
            }
            .offset(x: 122, y: 10)
        }
    }

    private func record(_ tint: Color, _ widths: [CGFloat]) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            SketchBar(width: widths[0], strength: 0.16)
            SketchBar(width: widths[1], strength: 0.08)
        }
    }
}
