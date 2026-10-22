import SwiftUI

/// The sheet register: a display-face title on white, then sections of rows grouped in bordered
/// boxes, every control the same height and one of two widths.
extension DesignTokens {
    static let sheetTitle = DisplayFont.font(size: 30, weight: .medium, relativeTo: .largeTitle)
    static let sheetTitleTracking: CGFloat = 0.2
    /// The white margin around a sheet's content and its action bar.
    static let sheetInset: CGFloat = 40
    /// Whitespace between a sheet's sections.
    static let sheetSectionSpacing: CGFloat = 28
    /// The inset inside a group, shared by its rows and the hairlines between them.
    static let sheetRowInset: CGFloat = 14
    /// A control that holds words: a name, a key, a menu.
    static let sheetFieldWidth: CGFloat = 260
    /// A control that holds a number.
    static let sheetNumberWidth: CGFloat = 120
    static let sheetControlRadius: CGFloat = 6
    static let sheetGroupRadius: CGFloat = 10
}
