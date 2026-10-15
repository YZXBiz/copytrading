import SwiftUI

/// Gain and loss colors for the curve and its readout: the palette's text-safe pair, so a change
/// read off the chart keeps AA contrast. Color never carries direction alone: readouts keep their
/// sign and arrow.
enum EquityTone {
    static let gain = Palette.gain
    static let loss = Palette.loss

    static func of(_ gain: Bool) -> Color { gain ? Self.gain : loss }

    static func of(change: Double) -> Color {
        change > 0 ? gain : change < 0 ? loss : Palette.tertiaryInk
    }
}
