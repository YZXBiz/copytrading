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
        case .neutral: .blue
        case .inactive: .secondary
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
