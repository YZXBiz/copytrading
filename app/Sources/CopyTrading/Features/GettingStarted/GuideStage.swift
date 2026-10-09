import SwiftUI

/// The five setup steps as posts along a hand-drawn ground, numbered underneath, with an ink dot
/// standing just short of the next one. It walks there when the page opens, and when a step is
/// done it hops and walks on to the following post. Nothing moves after that.
struct GuideStage: View {
    let progress: SetupProgress
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = SetupStep.allCases
    private let groundHeight: CGFloat = 72

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                InkGround(height: groundHeight)
                ForEach(steps) { step in
                    post(step)
                        .position(x: x(of: step.rawValue, in: width), y: groundHeight - 9)
                    Text(String(format: "%02d", step.rawValue + 1))
                        .font(DesignTokens.eyebrow)
                        .tracking(DesignTokens.eyebrowTracking)
                        .monospacedDigit()
                        .foregroundStyle(step == progress.next ? Palette.ink : Palette.tertiaryInk)
                        .position(x: x(of: step.rawValue, in: width), y: groundHeight + 16)
                }
                InkBead(hop: progress.completed)
                    .position(x: beadX(in: width), y: groundHeight - 6)
            }
        }
        .frame(height: groundHeight + 28)
        .onAppear {
            guard !reduceMotion else {
                arrived = true
                return
            }
            withAnimation(.easeInOut(duration: 1.2)) { arrived = true }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).delay(0.35), value: progress.completed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.string("Setup progress, %lld of %lld steps done", Int64(progress.completed), Int64(progress.total)))
    }

    /// Each post stands in the middle of its fifth of the ground.
    private func x(of index: Int, in width: CGFloat) -> CGFloat {
        width * (CGFloat(index) + 0.5) / CGFloat(steps.count)
    }

    /// Just short of the next post, or past the last one once everything is done; on the way in,
    /// it starts a step's width back.
    private func beadX(in width: CGFloat) -> CGFloat {
        let target = progress.next.map { x(of: $0.rawValue, in: width) - 30 } ?? width - 36
        return arrived ? target : max(14, target - width / CGFloat(steps.count))
    }

    /// A short ink post with a flag that is filled once its step is done.
    private func post(_ step: SetupStep) -> some View {
        let isDone = progress.isDone(step)
        return Canvas { context, size in
            var pole = Path()
            pole.move(to: CGPoint(x: 2, y: size.height))
            pole.addLine(to: CGPoint(x: 2, y: 1))
            context.stroke(pole, with: .color(Palette.ink), style: InkStroke.style)
            var flag = Path()
            flag.move(to: CGPoint(x: 2, y: 1))
            flag.addLine(to: CGPoint(x: size.width - 1, y: 5))
            flag.addLine(to: CGPoint(x: 2, y: 9))
            flag.closeSubpath()
            if isDone {
                context.fill(flag, with: .color(Palette.sage))
            }
            context.stroke(flag, with: .color(Palette.ink), style: InkStroke.style)
        }
        .frame(width: 13, height: 20)
        .offset(x: 5)
    }
}
