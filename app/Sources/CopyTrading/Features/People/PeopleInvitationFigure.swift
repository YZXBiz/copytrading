import SwiftUI

/// What People will hold, drawn on slips of paper: gurus as cards with their monogram, the channel
/// they post in, and a few lines of how to read them. Shapes only, no made-up people.
struct PeopleInvitationFigure: View {
    var body: some View {
        ZStack {
            card(name: "Alex", tilt: -4, lines: [110, 84, 96])
                .offset(x: -104, y: 6)
            card(name: "Sam", tilt: 3, lines: [92, 118])
                .offset(x: 18, y: -18)
            PaperSlip(tilt: -1.5) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Copies into"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                        SketchBar(width: 52)
                        Text("10%")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            .offset(x: 132, y: 58)
        }
    }

    private func card(name: String, tilt: Double, lines: [CGFloat]) -> some View {
        PaperSlip(tilt: tilt) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    GuruMonogram(name: name, size: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        SketchBar(width: 58, height: 7, strength: 0.22)
                        HStack(spacing: 3) {
                            Image(systemName: "number")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Palette.tertiaryInk)
                            SketchBar(width: 50, height: 5, strength: 0.1)
                        }
                    }
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, width in
                    SketchBar(width: width, strength: 0.09)
                }
            }
        }
    }
}
