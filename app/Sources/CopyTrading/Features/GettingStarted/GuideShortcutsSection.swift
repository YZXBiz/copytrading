import SwiftUI

/// Every keyboard shortcut, drawn as the keys to press.
struct GuideShortcutsSection: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            ForEach(GuideShortcut.all) { shortcut in
                GridRow {
                    HStack(spacing: 4) {
                        ForEach(shortcut.keys.enumerated(), id: \.offset) { _, key in
                            if key == "–" {
                                Text(L10n.string("to"))
                                    .font(DesignTokens.caption)
                                    .foregroundStyle(Palette.tertiaryInk)
                                    .padding(.horizontal, 2)
                            } else {
                                KeyCap(key)
                            }
                        }
                    }
                    .gridColumnAlignment(.trailing)
                    Text(L10n.string(shortcut.action))
                        .font(DesignTokens.documentBody)
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
