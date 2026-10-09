import AppKit
import SwiftUI

/// A neutral workspace, restrained reading/card surfaces, hairlines, and graphite ink in three strengths.
/// The accent is kept for links, switches, and the one primary action on a screen.
enum Palette {
    /// The soft off-white workspace mat around reading surfaces and the inset sidebar panel.
    static let canvas = dynamic(light: rgb(0xF3F3F3), dark: rgb(0x1C1C1E))
    /// Discrete white surfaces such as People cards and the Activity reading page.
    static let page = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x252527))
    /// A quiet inset for quoted source text and compact grouped controls.
    static let group = dynamic(light: rgb(0xF5F5F6), dark: rgb(0x2E2E30))
    /// The Settings page, a touch lighter than the workspace so the panel reads as its own place.
    static let panel = dynamic(light: rgb(0xF8F8F8), dark: rgb(0x1F1F21))
    /// Grouped settings rows sit in this soft well on `panel`.
    static let well = dynamic(light: rgb(0xEEEEEF), dark: rgb(0x2B2B2E))
    /// Row dividers.
    static let hairline = dynamic(light: rgb(0xDADADD), dark: NSColor(white: 1, alpha: 0.08))
    /// The selected row in a list (#D9E0ED).
    static let selection = dynamic(light: rgb(0xD9E0ED), dark: rgb(0x34405A))
    /// The selected row in the sidebar: a light grey pill, never the accent.
    static let sidebarSelection = dynamic(
        light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.1)
    )
    /// A soft hover cue for rows and tiles on the workspace canvas.
    static let hover = dynamic(light: rgb(0xE3E3E5), dark: rgb(0x343438))
    /// Titles and values (#1D1F21).
    static let ink = dynamic(light: rgb(0x1D1F21), dark: rgb(0xF2F2F3))
    /// Row labels and body text (#47494B).
    static let secondaryInk = dynamic(light: rgb(0x47494B), dark: rgb(0xC5C5C8))
    /// Captions, column headers, and icons (#858687).
    static let tertiaryInk = dynamic(light: rgb(0x5F6064), dark: rgb(0x8E8E93))
    /// Links, switches, and a screen's one primary action.
    static let accent = Color(red: 0.204, green: 0.471, blue: 0.965)
    /// What waits on the owner: a count beside a heading, a guru with calls to answer.
    /// The one warm fill, as a studio drawing uses it: inside an ink outline, on the thing the eye
    /// should land on (the gap that decided an order, how much of a limit is used, a step done).
    /// Never text and never a whole surface.
    static let butter = dynamic(light: rgb(0xF2D46B), dark: rgb(0xE3C25A))
    /// The riso set beside butter: soft fills at butter's own lightness, each with one meaning and
    /// always inside an ink outline with a shape of its own, so none depends on colour alone.
    /// Sage: it went through (a fill, a done step).
    static let sage = dynamic(light: rgb(0xB5D6A7), dark: rgb(0x8FB583))
    /// Blush: it was refused or failed.
    static let blush = dynamic(light: rgb(0xF3B4A2), dark: rgb(0xD98F7C))
    /// Sky: it is out with the broker, waiting on the market.
    static let sky = dynamic(light: rgb(0xB7D3EE), dark: rgb(0x86A9CC))
    static let amber = dynamic(light: rgb(0xB8860B), dark: rgb(0xF5C04A))

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}
