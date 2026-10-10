import AppKit
import SwiftUI

/// A long ID in small monospaced type, middle-truncated, with a button that copies it whole. The
/// button shows a check for a moment once the ID is on the clipboard.
struct CopyableIdentifierRow: View {
    let label: String
    let value: String
    @State private var copiedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TechnicalFactRow(label: label) {
            HStack(spacing: 6) {
                Text(value)
                    .font(DesignTokens.activityIdentifier)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(value)
                Button(
                    L10n.string("Copy %@ ID", L10n.string(label)), systemImage: copiedAt == nil ? "doc.on.doc" : "checkmark", action: copy
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(DesignTokens.activityMeta)
                .foregroundStyle(copiedAt == nil ? Palette.tertiaryInk : Palette.ink)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .help(L10n.string("Copy"))
            }
        }
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copiedAt = nil
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedAt = .now
    }
}
