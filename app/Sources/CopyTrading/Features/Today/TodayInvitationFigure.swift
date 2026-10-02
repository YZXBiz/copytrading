import SwiftUI

/// What Today will hold, drawn on slips of paper: a balance with its line, a guru's post, and an
/// account's limit. Shapes only, no made-up numbers.
struct TodayInvitationFigure: View {
    var body: some View {
        ZStack {
            PaperSlip(tilt: -3) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.string("Balance"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                    SketchBar(width: 92, height: 11, strength: 0.18)
                    RisingLineFlourish(lineWidth: 2)
                        .frame(width: 160, height: 42)
                }
            }
            .offset(x: -88, y: 4)
            PaperSlip(tilt: 3) {
                HStack(alignment: .top, spacing: 8) {
                    GuruMonogram(name: "Guru", size: 20)
                    VStack(alignment: .leading, spacing: 5) {
                        SketchBar(width: 54)
                        SketchBar(width: 104, strength: 0.09)
                        SketchBar(width: 80, strength: 0.09)
                        Text(L10n.string("Copied"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14), in: .capsule)
                    }
                }
            }
            .offset(x: 104, y: -26)
            PaperSlip(tilt: 1.5) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Limits"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.ink.opacity(0.08)).frame(width: 110, height: 5)
                        Capsule().fill(Palette.accent.opacity(0.7)).frame(width: 46, height: 5)
                    }
                }
            }
            .offset(x: 112, y: 58)
        }
    }
}
