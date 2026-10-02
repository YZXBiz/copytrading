import AppKit
import SwiftUI

/// Identity colors for up to three accounts, in a fixed order validated for color-vision
/// deficiency on both page surfaces. Green, red, and orange stay reserved for gain, loss, and live money.
enum AccountSeriesColor {
    static let slots: [Color] = [
        dynamic(light: 0x2A78D6, dark: 0x3987E5),
        dynamic(light: 0xEDA100, dark: 0xC98500),
        dynamic(light: 0xE87BA4, dark: 0xD55181),
    ]

    /// Accounts past the third fold into one neutral series.
    static let other = Palette.tertiaryInk

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            })
    }
}
