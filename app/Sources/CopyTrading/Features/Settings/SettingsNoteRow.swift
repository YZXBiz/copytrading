import SwiftUI

/// A notice inside a well: a problem to look at, or where a running task has got to.
struct SettingsNoteRow: View {
    let text: String
    var tone: StatusTone = .neutral
    var isWorking = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: tone == .neutral ? "info.circle" : tone.symbol)
                    .foregroundStyle(tone == .neutral ? Palette.tertiaryInk : tone.color)
                    .accessibilityHidden(true)
            }
            Text(L10n.string(text))
                .font(.body)
                .foregroundStyle(tone == .neutral ? Palette.secondaryInk : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
