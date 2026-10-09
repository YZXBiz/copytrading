import SwiftUI

/// The sheet register: a display-face title on white, then content ruled by hairlines.
extension DesignTokens {
    static let sheetTitle = DisplayFont.font(size: 36, weight: .medium, relativeTo: .largeTitle)
    static let sheetTitleTracking: CGFloat = 0.2
    /// The white margin around a sheet's content and its action bar.
    static let sheetInset: CGFloat = 40
    /// Whitespace between a sheet's sections; a hairline sits at the top of each.
    static let sheetSectionSpacing: CGFloat = 34
}
