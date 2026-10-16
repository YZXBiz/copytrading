import CoreGraphics
import Testing

/// The assistant (380 points wide, inset 8) covers the page's trailing side; a Connections panel
/// opened beside it stays clear of it at every window width the app allows.
@Test func aConnectionsPanelStaysClearOfTheAssistant() {
    let covered: CGFloat = 380 + 8
    // From the narrowest window with the sidebar (980 − 268) to a wide one without it.
    for pageWidth in stride(from: CGFloat(712), through: 1_900, by: 47) {
        let placement = ConnectionPanelPlacement(pageWidth: pageWidth, coveredTrailing: covered)
        #expect(placement.maxX <= pageWidth - covered, "At \(pageWidth) the panel ran under the assistant")
        #expect(placement.minX >= ConnectionPanelPlacement.margin, "At \(pageWidth) the panel left the page")
        #expect(placement.width >= ConnectionPanelPlacement.narrowest)
    }
    let alone = ConnectionPanelPlacement(pageWidth: 912, coveredTrailing: 0)
    #expect(alone == ConnectionPanelPlacement(pageWidth: 912, coveredTrailing: 0))
    #expect(alone.width == ConnectionPanelPlacement.fullWidth && alone.centerX == 456, "Without the assistant the panel moved")
}
