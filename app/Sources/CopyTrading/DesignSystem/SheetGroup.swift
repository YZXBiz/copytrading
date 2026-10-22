import SwiftUI

/// A section's rows in one bordered box with a hairline between each, as a settings form groups
/// its fields. Every row gets the same inset, so names and controls line up down the sheet.
struct SheetGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Group(subviews: content) { rows in
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                            .padding(.leading, DesignTokens.sheetRowInset)
                    }
                    row
                        .padding(.horizontal, DesignTokens.sheetRowInset)
                }
            }
        }
        .background(Palette.page, in: .rect(cornerRadius: DesignTokens.sheetGroupRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.sheetGroupRadius)
                .strokeBorder(Palette.hairline)
        }
    }
}
