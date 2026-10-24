import SwiftUI

/// CopyTrading came back with copying paused, and copying was on when it last stopped. Copying
/// never starts without the owner, so the banner says so and starts it in one press: the same
/// checks and Touch ID as Start Copying. It stays until copying runs or the owner dismisses it.
struct CopyingStoppedBanner: View {
    let model: AppModel
    let accountFeature: AccountFeatureModel

    var body: some View {
        if model.showsCopyingStopped {
            HStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
                Text(L10n.string("Copying paused when CopyTrading quit."))
                Spacer(minLength: 8)
                Button(L10n.string("Start Copying")) {
                    Task { await model.startCopyingEverywhere(feature: accountFeature) }
                }
                .buttonStyle(PageButtonStyle(emphasis: .prominent))
                .accessibilityIdentifier("copyingStopped.start")
                Button(L10n.string("Dismiss"), systemImage: "xmark", action: model.dismissCopyingStopped)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(L10n.string("Dismiss"))
                    .accessibilityIdentifier("copyingStopped.dismiss")
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.canvas)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("copyingStopped.banner")
        }
    }
}
