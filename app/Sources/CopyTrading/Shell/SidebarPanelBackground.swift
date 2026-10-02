import SwiftUI

/// The sidebar's inset floating panel: a soft grey rounded sheet with a fine
/// edge on the workspace canvas. The main sidebar and the Settings sidebar share it.
struct SidebarPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    private var fill: Color {
        colorScheme == .dark
            ? Palette.canvas.mix(with: Palette.page, by: 0.35)
            : Color(red: 237 / 255.0, green: 239 / 255.0, blue: 240 / 255.0)
    }

    private var edge: Color {
        if contrast == .increased { return Palette.secondaryInk }
        return colorScheme == .dark
            ? Palette.hairline
            : Color(red: 213 / 255.0, green: 217 / 255.0, blue: 219 / 255.0)
    }

    var body: some View {
        ZStack {
            Palette.canvas
            RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.panelCornerRadius)
                        .strokeBorder(edge, lineWidth: contrast == .increased ? 1 : 1 / displayScale)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
