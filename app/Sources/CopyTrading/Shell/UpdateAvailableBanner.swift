import SwiftUI

/// A newer CopyTrading, offered in the window: no trip to Settings. Install opens the update with
/// its release notes; Later puts this version off until the next launch.
struct UpdateAvailableBanner: View {
    let model: AppModel
    @Environment(\.appUpdater) private var updater

    var body: some View {
        if let version = updater.offer.version {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("CopyTrading %@ is ready to install.", version))
                    if let note = model.updateCopyingNote {
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(L10n.string("Later"), action: updater.offer.postpone)
                    .accessibilityIdentifier("update.later")
                Button(L10n.string("Install Update…"), action: updater.installOfferedUpdate)
                    .buttonStyle(PageButtonStyle(isProminent: true))
                    .accessibilityIdentifier("update.install")
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.canvas)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("update.banner")
        }
    }
}
