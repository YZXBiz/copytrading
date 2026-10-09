import SwiftUI

/// A short drawn ink stroke that opens a part of a sheet, like a chapter tick. It marks where a
/// section starts without running a grey rule across the page, so the only full-width line left in
/// a sheet is the one a field writes on.
struct SectionMark: View {
    var body: some View {
        Canvas { context, size in
            var stroke = Path()
            stroke.move(to: CGPoint(x: InkStroke.width / 2, y: size.height / 2))
            stroke.addLine(to: CGPoint(x: size.width - InkStroke.width / 2, y: size.height / 2))
            context.stroke(stroke, with: .color(Palette.ink), style: InkStroke.style)
        }
        .frame(width: 18, height: InkStroke.width)
        .accessibilityHidden(true)
    }
}
