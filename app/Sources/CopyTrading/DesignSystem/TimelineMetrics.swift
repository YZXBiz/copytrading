import CoreGraphics

/// The fixed columns every timeline row shares, so times, dots, and outcomes line up down the page.
enum TimelineMetrics {
    /// The time gutter on the left, wide enough for "10:02:40 AM" and a day label.
    static let gutter: CGFloat = 104
    /// The rail's own column between the gutter and the words.
    static let rail: CGFloat = 36
    static let dot: CGFloat = 11
    /// Below this width a row stacks its outcomes under its words instead of beside them.
    static let wideWidth: CGFloat = 680
}
