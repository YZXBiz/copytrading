import SwiftUI

/// A reading with nothing to change, on one line: the name at the leading edge and its value at
/// the trailing edge, with any explanation under the name. VoiceOver hears both together,
/// "Local engine, Ready".
struct SettingsValueRow: View {
    let label: String
    let value: String
    var detail: String?
    var tone: StatusTone?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(label))
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(L10n.string(detail))
                        .font(.body)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if let tone {
                    Image(systemName: tone.symbol)
                        .imageScale(.small)
                        .foregroundStyle(tone.color)
                }
                Text(value)
                    .font(DesignTokens.bodyText)
                    .foregroundStyle(Palette.secondaryInk)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("%@, %@", L10n.string(label), value))
        .accessibilityHint(detail.map { L10n.string($0) } ?? "")
    }
}
