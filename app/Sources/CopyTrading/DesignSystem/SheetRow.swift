import SwiftUI

/// One setting in a sheet: its name and a plain line on what it does at the leading edge, its
/// control at the trailing edge. Rows are parted by whitespace, never by lines.
struct SheetRow<Trailing: View>: View {
    let title: String
    var hint: String?
    /// One worked example behind an "i" beside the name.
    var example: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(DesignTokens.rowTitle)
                        .foregroundStyle(Palette.ink)
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
