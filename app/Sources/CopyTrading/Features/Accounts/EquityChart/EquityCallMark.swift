import Foundation

/// A waiting call pinned on the chart at the moment its guru posted it, so the owner sees where the
/// balance stood when the call came in.
struct EquityCallMark: Equatable, Identifiable {
    /// The post's source ID, which its ticket on the page shares.
    let id: String
    let at: Date
    /// "Call · 9:45 PM".
    let label: String
}
