import SwiftUI

/// One row of a timeline that reads top to bottom: the time in a gutter on the left, a dot on the
/// ink rail that joins the rows, the words in the middle, and what came of it in a fixed column on
/// the right. A narrow page moves that column under the words.
struct TimelineRow<Gutter: View, Content: View, Trailing: View>: View {
    /// The row's dot; nil draws the rail through without one, as under a day's label.
    let mark: TimelineMark?
    /// Whether the rail carries on above and below this row's dot.
    let runsAbove: Bool
    let runsBelow: Bool
    let isWide: Bool
    var trailingWidth: CGFloat = 300
    /// Space above and below inside the row, so the rail runs unbroken from one row to the next.
    var top: CGFloat = 14
    var bottom: CGFloat = 14
    @ViewBuilder let gutter: Gutter
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    /// The ink pen with square ends, so one row's rail meets the next without a darker joint.
    private static var rail: StrokeStyle { StrokeStyle(lineWidth: InkStroke.width, lineCap: .butt) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            gutter
                .frame(width: TimelineMetrics.gutter, alignment: .trailing)
            dot
                .frame(width: TimelineMetrics.rail)
            if isWide {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                    .frame(width: trailingWidth, alignment: .trailing)
                    .padding(.leading, trailingWidth > 0 ? 24 : 0)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    content
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, top)
        .padding(.bottom, bottom)
        .backgroundPreferenceValue(TimelineDotAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let center = proxy[anchor]
                    Path { path in
                        path.move(to: CGPoint(x: center.x, y: runsAbove ? 0 : center.y))
                        path.addLine(to: CGPoint(x: center.x, y: runsBelow ? proxy.size.height : center.y))
                    }
                    .stroke(Palette.ink.opacity(0.55), style: Self.rail)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Sits a little above the time's baseline, at the middle of its digits.
    private var dot: some View {
        Group {
            switch mark {
            case .traded:
                Circle()
                    .fill(Palette.butter)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: InkStroke.width))
            case .waiting:
                Circle()
                    .fill(Palette.page)
                    .overlay(Circle().strokeBorder(Palette.amber, lineWidth: InkStroke.width))
            case .quiet:
                Circle()
                    .fill(Palette.page)
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: InkStroke.width))
            case nil:
                Color.clear
            }
        }
        .frame(width: TimelineMetrics.dot, height: TimelineMetrics.dot)
        .anchorPreference(key: TimelineDotAnchor.self, value: .center) { $0 }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
        .accessibilityHidden(true)
    }
}
