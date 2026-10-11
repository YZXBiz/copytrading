import SwiftUI

/// Where a post in flight has got to, on one ink line with its four stops named under it: Read,
/// Sized, Sent, Filled. Stops behind the post are solid ink, the one it is at is the butter bead,
/// and the stops ahead are hollow. While the order waits at Alpaca a butter fill grows along the
/// Sent–Filled stretch with the time over it, so the wait is something you can see.
struct PostStageLine: View {
    /// 0 in line to be read, 1 reading, 2 sizing, 3 waiting for a fill, 4 filled.
    let stage: Int
    /// How far the fill wait has come, 0…1, while the order waits at Alpaca.
    var fillWait: Double?
    /// "23 s of 60 s", over the Sent–Filled stretch.
    var waitText: String?
    /// The stop waits on the owner: its name reads in amber.
    var waitsOnOwner = false
    var hops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let inset: CGFloat = 26
    private static let lineY: CGFloat = 30

    /// The stop the bead stands on: Read while read, Sized while sized, Filled once filled.
    private var current: Int {
        switch stage {
        case ...1: 0
        case 2: 1
        case 3: 2
        default: 3
        }
    }

    private func isDone(_ stop: Int) -> Bool {
        stage >= 4 || stop < current || (stage == 3 && stop == 2)
    }

    var body: some View {
        let titles = [L10n.string("Read"), L10n.string("Sized"), L10n.string("Sent"), L10n.string("Filled")]
        GeometryReader { proxy in
            let step = (proxy.size.width - Self.inset * 2) / 3
            let x: (Int) -> CGFloat = { Self.inset + CGFloat($0) * step }
            let waiting = stage == 3
            let head = waiting ? x(2) + step * CGFloat(min(max(fillWait ?? 0, 0), 1)) : x(current)
            ZStack(alignment: .topLeading) {
                line(from: x(0), to: x(3), color: Palette.hairline)
                line(from: x(0), to: waiting ? x(2) : head, color: Palette.ink)
                if waiting {
                    // The wait at Alpaca, filling the stretch toward Filled as the seconds pass.
                    Capsule()
                        .fill(Palette.butter)
                        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: InkStroke.width))
                        .frame(width: max(head - x(2) + 10, 12), height: 12)
                        .position(x: (x(2) - 5 + head + 5) / 2, y: Self.lineY)
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: head)
                    if let waitText {
                        Text(waitText)
                            .font(DesignTokens.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .fixedSize()
                            .position(x: (x(2) + x(3)) / 2, y: 9)
                    }
                }
                ForEach(0..<4, id: \.self) { stop in
                    dot(stop)
                        .position(x: x(stop), y: Self.lineY)
                    Text(titles[stop])
                        .font(DesignTokens.caption.weight(stop == current ? .semibold : .medium))
                        .foregroundStyle(labelColor(stop))
                        .fixedSize()
                        .position(x: x(stop), y: Self.lineY + 22)
                }
                InkBead(hop: hops)
                    .position(x: head, y: Self.lineY)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: current)
            }
        }
        .frame(height: Self.lineY + 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titles[current])
    }

    private func line(from start: CGFloat, to end: CGFloat, color: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: start, y: Self.lineY))
            path.addLine(to: CGPoint(x: max(start, end), y: Self.lineY))
        }
        .stroke(color, style: InkStroke.style)
    }

    @ViewBuilder
    private func dot(_ stop: Int) -> some View {
        if isDone(stop) {
            Circle().fill(Palette.ink).frame(width: 9, height: 9)
        } else {
            Circle()
                .strokeBorder(Palette.tertiaryInk, lineWidth: 1.4)
                .background(Circle().fill(Palette.page))
                .frame(width: 10, height: 10)
        }
    }

    private func labelColor(_ stop: Int) -> Color {
        if stop == current, waitsOnOwner { return Palette.amber }
        return isDone(stop) || stop == current ? Palette.ink : Palette.tertiaryInk
    }
}
