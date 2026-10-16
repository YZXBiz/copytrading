import SwiftUI

/// One setting in a sheet: its name and a plain line on what it does at the leading edge, its
/// control at the trailing edge. Rows are parted by whitespace, never by lines.
struct SheetRow<Trailing: View>: View {
    let title: String
    var hint: String?
    /// One worked example behind an "i" beside the name.
    var example: String?
    /// The trailing control carries the title, so VoiceOver reads it once, on the control. The
    /// hint stays readable text.
    var labelsControl = false
    /// The trailing side only shows a value, so VoiceOver hears the row as one reading:
    /// "Requested by, claude".
    var isReading = false
    @ViewBuilder let trailing: Trailing

    @ViewBuilder var body: some View {
        if isReading {
            row.accessibilityElement(children: .combine)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(DesignTokens.rowTitle)
                        .foregroundStyle(Palette.ink)
                        .accessibilityHidden(labelsControl)
                    if let example {
                        ExampleMark(title: title, example: example)
                    }
                }
                if let hint {
                    Text(hint)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 12)
    }
}
