import AppKit
import SwiftUI

/// Every color that carries a meaning in text (ink, money up and down, live, waiting) keeps WCAG AA,
/// 4.5:1, on every surface it sits on, in light and in dark.
@MainActor
func runPaletteContrastTests() throws {
    let texts: [(String, Color)] = [
        ("ink", Palette.ink), ("secondary ink", Palette.secondaryInk), ("tertiary ink", Palette.tertiaryInk),
        ("gain", Palette.gain), ("loss", Palette.loss), ("live", Palette.live), ("amber", Palette.amber),
    ]
    let surfaces: [(String, Color)] = [
        ("page", Palette.page), ("canvas", Palette.canvas), ("group", Palette.group), ("panel", Palette.panel),
        ("well", Palette.well),
    ]
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        for (textName, text) in texts {
            for (surfaceName, surface) in surfaces {
                let ratio = contrast(text, surface, in: appearance)
                guard ratio >= 4.5 else {
                    throw PaletteContrastFailure(
                        description: "\(textName) on \(surfaceName) in \(appearance.rawValue) is \(ratio) to 1")
                }
            }
        }
    }
    print("CopyTradingContractTests: every meaning-carrying text color keeps 4.5:1 on every surface, light and dark")
}

private struct PaletteContrastFailure: Error, CustomStringConvertible {
    let description: String
}

private func contrast(_ a: Color, _ b: Color, in appearance: NSAppearance.Name) -> Double {
    let lighter = max(luminance(a, appearance), luminance(b, appearance))
    let darker = min(luminance(a, appearance), luminance(b, appearance))
    return (lighter + 0.05) / (darker + 0.05)
}

private func luminance(_ color: Color, _ appearance: NSAppearance.Name) -> Double {
    var rgb: (Double, Double, Double) = (0, 0, 0)
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        rgb = (Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent))
    }
    func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
}
