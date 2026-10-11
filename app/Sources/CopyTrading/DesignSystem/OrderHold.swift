import SwiftUI

/// A few seconds between the owner's tap and the order leaving for Alpaca, so a slip can be taken
/// back: what is about to be sent, an ink line that drains as the seconds run out, and Undo.
/// When the line runs out, `send` runs once; Undo or Escape calls `undo` and nothing is sent.
struct OrderHold: View {
    let title: String
    let seconds: TimeInterval
    let send: () -> Void
    let undo: () -> Void
    @State private var started = Date.now
    @State private var isDone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The owner's choice under Settings → While Copying; zero sends at once.
    static let settingKey = "orders.holdSeconds"
    static var chosenSeconds: TimeInterval {
        UserDefaults.standard.object(forKey: settingKey) as? Double ?? 5
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isDone)) { context in
            let left = max(0, seconds - context.date.timeIntervalSince(started))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(DesignTokens.bodyEmphasis)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(L10n.string("Sending in %lld s", Int64(left.rounded(.up))))
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                        .monospacedDigit()
                    Spacer(minLength: 12)
                    Button(L10n.string("Undo"), action: cancel)
                        .buttonStyle(QuietTextButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("orderHold.undo")
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: proxy.size.width * (seconds > 0 ? left / seconds : 0), height: InkStroke.width)
                }
                .frame(height: InkStroke.width)
                .accessibilityHidden(true)
            }
            .onChange(of: left == 0) { _, finished in
                if finished { fire() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("%@, sending soon", title))
    }

    private func fire() {
        guard !isDone else { return }
        isDone = true
        send()
    }

    private func cancel() {
        guard !isDone else { return }
        isDone = true
        undo()
    }
}
