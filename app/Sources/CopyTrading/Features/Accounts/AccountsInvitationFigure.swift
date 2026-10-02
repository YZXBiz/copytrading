import SwiftUI

/// What Accounts will hold, drawn on slips of paper: a broker account marked Paper with its
/// balance and a limit, and the positions it holds. Shapes only, no made-up money.
struct AccountsInvitationFigure: View {
    var body: some View {
        ZStack {
            PaperSlip(tilt: -3) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Palette.accent.gradient, in: .rect(cornerRadius: 6))
                        SketchBar(width: 48, height: 7, strength: 0.22)
                        Text(L10n.string("Paper"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Palette.hairline))
                    }
                    Text(L10n.string("Balance"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                    SketchBar(width: 104, height: 12, strength: 0.18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("Daily loss cap"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.ink.opacity(0.08)).frame(width: 130, height: 5)
                            Capsule().fill(Color.green.opacity(0.7)).frame(width: 30, height: 5)
                        }
                    }
                }
            }
            .offset(x: -82, y: 2)
            PaperSlip(tilt: 2.5) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.string("Positions"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                    ForEach([62, 48, 56], id: \.self) { width in
                        HStack(spacing: 18) {
                            SketchBar(width: 28, strength: 0.22)
                            SketchBar(width: CGFloat(width), strength: 0.09)
                        }
                    }
                }
            }
            .offset(x: 118, y: 14)
        }
    }
}
