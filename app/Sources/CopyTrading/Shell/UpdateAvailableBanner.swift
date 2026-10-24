import SwiftUI

/// A newer CopyTrading, offered in the window: no trip to Settings. Install opens the update with
/// its release notes; Later puts this version off until the next launch. In a folder macOS
/// guards, the update can't install, so the banner says to move the app and shows it in Finder.
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
                    if let folder = updater.offer.blockingFolder {
                        Text(L10n.string("CopyTrading %@ is out, but can't install in %@.", version, folder))
                        Text(L10n.string("Move CopyTrading to Applications, then open it from there to install."))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.string("CopyTrading %@ is ready to install.", version))
                        if let note = model.updateCopyingNote {
                            Text(note)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                Button(L10n.string("Later"), action: updater.offer.postpone)
                    .accessibilityIdentifier("update.later")
                if updater.offer.blockingFolder != nil {
                    Button(L10n.string("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    .buttonStyle(PageButtonStyle(emphasis: .prominent))
                    .accessibilityIdentifier("update.reveal")
                } else {
                    Button(L10n.string("Install Update…"), action: updater.installOfferedUpdate)
                        .buttonStyle(PageButtonStyle(emphasis: .prominent))
                        .accessibilityIdentifier("update.install")
                }
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
