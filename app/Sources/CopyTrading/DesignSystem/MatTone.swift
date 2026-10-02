import SwiftUI

/// The colours a card's mat fades between: a soft hue at
/// the top that settles toward a quiet grey at the bottom.
struct MatTone: Equatable {
    let top: Color
    let bottom: Color

    static let sky = MatTone(top: rgb(0xA7C7E1), bottom: rgb(0xD2DADB))
    static let sage = MatTone(top: rgb(0xB5D3C0), bottom: rgb(0xD6DDD8))
    static let lilac = MatTone(top: rgb(0xC9C1E4), bottom: rgb(0xDBD9E2))
    static let peach = MatTone(top: rgb(0xE9CBB3), bottom: rgb(0xE2DCD6))
    static let rose = MatTone(top: rgb(0xE6BFC8), bottom: rgb(0xE1D9DB))

    private static let named: [MatTone] = [.sky, .sage, .lilac, .peach, .rose]

    /// The same tone for the same name everywhere it appears.
    static func named(_ name: String) -> MatTone {
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return named[seed % named.count]
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
