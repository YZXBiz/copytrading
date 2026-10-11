import CoreText
import Foundation
import SwiftUI

/// The display face: Josefin Sans (SIL Open Font License), a geometric sans for names, the
/// balance, and section titles. Body text and controls stay in the system font.
enum DisplayFont {
    static let family = "Josefin Sans"

    /// Registers the bundled face once, for this process only; nothing is installed on the Mac.
    static let isRegistered: Bool = {
        guard let url = Bundle.module.url(forResource: "JosefinSans", withExtension: "ttf", subdirectory: "Fonts") else {
            return false
        }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// The face at a size that follows Dynamic Type from `style`; the system font if the bundle
    /// is missing, so text never disappears.
    static func font(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle) -> Font {
        guard isRegistered else { return .system(size: size, weight: weight) }
        return .custom(family, size: size, relativeTo: style).weight(weight)
    }
}
