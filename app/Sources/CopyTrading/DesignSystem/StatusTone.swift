import SwiftUI

/// The small set of meanings a status can carry; every badge, tile, and callout maps to one.
enum StatusTone: Equatable {
    case positive
    case caution
    case critical
    case neutral
    case inactive

    var color: Color {
        switch self {
        case .positive: .green
        case .caution: .orange
        case .critical: .red
        case .neutral: Palette.secondaryInk
        case .inactive: .secondary
        }
    }

    /// The riso fill a status dot carries inside its ink outline: sage when it works, butter when
    /// it wants a look, blush when it failed, sky while it is under way; nothing while it waits.
    var fill: Color? {
        switch self {
        case .positive: Palette.sage
        case .caution: Palette.butter
        case .critical: Palette.blush
        case .neutral: Palette.sky
        case .inactive: nil
        }
    }

    /// Symbols differ per tone so status never depends on color alone.
    var symbol: String {
        switch self {
        case .positive: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .neutral: "info.circle.fill"
        case .inactive: "pause.circle.fill"
        }
    }
}
