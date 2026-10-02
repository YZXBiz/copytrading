import AppKit
import SwiftUI

/// Where the records live, said the way Finder would: a folder, its name, and a short path that
/// keeps both ends when it has to shorten. The whole path shows on hover and copies as text.
struct DataFolderRow: View {
    let path: String

    private var shortPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Palette.accent.gradient)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("CopyTrading data"))
                    .font(DesignTokens.bodyEmphasis)
                    .foregroundStyle(Palette.ink)
                Text(shortPath)
                    .font(DesignTokens.caption.monospaced())
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("CopyTrading data, %@", shortPath))
            Button(L10n.string("Show in Finder"), action: showInFinder)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }
}
