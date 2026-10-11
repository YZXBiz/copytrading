import SwiftUI

/// Where a timeline row's dot sits, so the rail behind the row can run through its centre.
struct TimelineDotAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}
