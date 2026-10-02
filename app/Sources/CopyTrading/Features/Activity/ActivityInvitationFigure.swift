import SwiftUI

/// What Activity will hold, drawn on slips of paper: a few posts from gurus, each with what the
/// accounts did about it. Shapes only, no made-up posts.
struct ActivityInvitationFigure: View {
    var body: some View {
        ZStack {
            post(guru: "Alex", tilt: -3, lines: [96, 132, 70]) {
                chip("Copied into primary", tint: .green)
            }
            .offset(x: -96, y: -8)
            post(guru: "Sam", tilt: 2.5, lines: [80, 118]) {
                chip("Skipped", tint: Palette.tertiaryInk)
            }
            .offset(x: 104, y: -30)
            post(guru: "Rae", tilt: -1.5, lines: [70, 100]) {
                chip("Needs review", tint: .orange)
            }
            .offset(x: 92, y: 56)
        }
    }

    private func post(guru: String, tilt: Double, lines: [CGFloat], @ViewBuilder outcome: () -> some View) -> some View {
        PaperSlip(tilt: tilt) {
            HStack(alignment: .top, spacing: 8) {
                GuruMonogram(name: guru, size: 20)
                VStack(alignment: .leading, spacing: 5) {
                    SketchBar(width: 46, strength: 0.2)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, width in
                        SketchBar(width: width, strength: 0.09)
                    }
                    outcome()
                        .padding(.top, 2)
                }
            }
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(L10n.string(text))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: .capsule)
    }
}
