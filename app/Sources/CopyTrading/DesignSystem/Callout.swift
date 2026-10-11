import SwiftUI

/// An inline notice on the page itself, with no box: its symbol, then the words. Neutral callouts
/// explain in grey; caution and critical ones put their colour on the symbol and read in ink.
struct Callout: View {
    let text: String
    var tone: StatusTone = .neutral

    init(_ text: String, tone: StatusTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(tone == .neutral ? Palette.secondaryInk : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: tone == .neutral ? "info.circle" : tone.symbol)
                .foregroundStyle(tone == .neutral ? Palette.tertiaryInk : tone.color)
        }
        .font(.callout)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
