import SwiftUI

/// One post as Activity lists it, for the guide's picture of Activity.
struct GuideActivityLine: View {
    let author: String
    let time: String
    let text: String
    let outcome: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GuruMonogram(name: author, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(author)
                        .font(DesignTokens.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 4)
                    Text(time)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                }
                Text(text)
                    .font(DesignTokens.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Label(outcome, systemImage: tone.symbol)
                    .font(DesignTokens.caption)
                    .imageScale(.small)
                    .foregroundStyle(tone.color)
            }
        }
        .padding(10)
        .background(Palette.page, in: .rect(cornerRadius: 8))
    }
}
