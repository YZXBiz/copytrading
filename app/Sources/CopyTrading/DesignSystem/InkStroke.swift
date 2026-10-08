import SwiftUI

/// The one pen every drawing on a page uses: a thin ink line with round ends, as if drawn by hand.
enum InkStroke {
    static let width: CGFloat = 1.8
    static let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
}
