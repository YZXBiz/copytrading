import SwiftUI

/// The bounds of every card a Connections panel can grow from, read only when a panel opens or
/// closes.
struct ConnectionOriginKey: PreferenceKey {
    static let defaultValue: [ConnectionPanelOrigin: Anchor<CGRect>] = [:]

    static func reduce(value: inout [ConnectionPanelOrigin: Anchor<CGRect>], nextValue: () -> [ConnectionPanelOrigin: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
