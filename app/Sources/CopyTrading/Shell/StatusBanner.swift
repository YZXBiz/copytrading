import SwiftUI

/// One place for the model's latest status message instead of a "Status" section on every screen.
/// It stays until dismissed: anything worth a banner is worth reading.
struct StatusBanner: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message = model.message {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // The message reads as one element; Dismiss stays its own button.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Palette.secondaryInk)
                        Text(message)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L10n.string("Platform status: %@", message))
                    Spacer(minLength: 8)
                    Button(L10n.string("Dismiss"), systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(L10n.string("Dismiss"))
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Divider()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: model.message)
    }

    private func dismiss() {
        model.message = nil
    }
}
