import SwiftUI

/// A small rising equity line with a soft wash, for the guide's picture of Today.
struct GuideSparkline: View {
    private let points: [Double] = [0.30, 0.34, 0.31, 0.42, 0.40, 0.52, 0.49, 0.61, 0.58, 0.70, 0.74, 0.82]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let step = size.width / Double(points.count - 1)
            var line = Path()
            for (index, value) in points.enumerated() {
                let point = CGPoint(x: Double(index) * step, y: size.height * (1 - value))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var wash = line
            wash.addLine(to: CGPoint(x: size.width, y: size.height))
            wash.addLine(to: CGPoint(x: 0, y: size.height))
            wash.closeSubpath()
            context.fill(
                wash,
                with: .linearGradient(
                    Gradient(colors: [Color.green.opacity(0.22), Color.green.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(.green), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 54)
        .accessibilityHidden(true)
    }
}
