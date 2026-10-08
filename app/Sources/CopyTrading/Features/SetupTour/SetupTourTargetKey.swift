import SwiftUI

/// Where each tour target sits, collected from the views that carry one.
struct SetupTourTargetKey: PreferenceKey {
    static let defaultValue: [SetupTourTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [SetupTourTarget: Anchor<CGRect>], nextValue: () -> [SetupTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as the place the setup tour points at for `target`; nil marks nothing.
    /// Targets inside it are kept, so a section can be one target and a row in it another.
    func setupTourTarget(_ target: SetupTourTarget?) -> some View {
        transformAnchorPreference(key: SetupTourTargetKey.self, value: .bounds) { targets, anchor in
            if let target { targets[target] = anchor }
        }
    }
}
