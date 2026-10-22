import SwiftUI

extension View {
    /// A sheet's text or number field: plain text in a soft well, one height everywhere, and the
    /// width of its kind (`sheetFieldWidth` for words, `sheetNumberWidth` for numbers).
    func sheetInput(width: CGFloat = DesignTokens.sheetFieldWidth) -> some View {
        labelsHidden()
            .textFieldStyle(.plain)
            .font(DesignTokens.bodyText)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Palette.well, in: .rect(cornerRadius: DesignTokens.sheetControlRadius))
            .frame(width: width)
    }
}
