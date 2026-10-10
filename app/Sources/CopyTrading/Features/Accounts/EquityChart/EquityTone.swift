import SwiftUI

/// Gain and loss colors for the curve, toned toward ink so large fills stay calm.
/// Color never carries direction alone: readouts keep their sign and arrow.
enum EquityTone {
    static let gain = Color.green.mix(with: Palette.ink, by: 0.24)
    static let loss = Color.red.mix(with: Palette.ink, by: 0.18)

    static func of(_ gain: Bool) -> Color { gain ? Self.gain : loss }

    static func of(change: Double) -> Color {
        change > 0 ? gain : change < 0 ? loss : Palette.tertiaryInk
    }
}
