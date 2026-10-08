/// Shared layout constants so every screen uses the same rhythm.
import SwiftUI

enum DesignTokens {
    /// A stable inset from the detail column, shared by page headers and their content.
    static let pagePadding: CGFloat = 26
    static let todayContentMaxWidth: CGFloat = 1_040
    static let todayTimelineMinWidth: CGFloat = 320
    static let todayLimitsWidth: CGFloat = 248
    static let workingSurfacePadding: CGFloat = 24
    static let personCardMinWidth: CGFloat = 280
    static let personCardMaxWidth: CGFloat = 340
    static let personGallerySpacing: CGFloat = 18
    static let peopleContentMaxWidth: CGFloat = 1_440
    static let accountsContentMaxWidth: CGFloat = 1_480
    /// Activity reads like a document inside the wider inspection lane.
    static let readingContentMaxWidth: CGFloat = 720
    static let calloutCornerRadius: CGFloat = 8
    static let blockCornerRadius: CGFloat = 10
    static let readingCornerRadius: CGFloat = 12
    /// The gap between the toolbar and a screen's header row.
    static let pageTopPadding: CGFloat = 4
    static let pageSectionSpacing: CGFloat = 20
    static let panelSpacing: CGFloat = 18
    static let headerControlSize: CGFloat = 30
    /// The rounded-square page controls: ⊕ on Connections, close and back in Settings.
    static let squareControlSize: CGFloat = 34
    /// The rounded panels Connections and Settings draw their pages on, matching the sidebar's.
    static let panelCornerRadius: CGFloat = 22

    // Semantic system styles keep the platform's text and legibility preferences. Scale from
    // macOS's native defaults to the workspace's compact reading hierarchy. Titles are set in
    // New York, as the invitations are; everything people read and press stays in SF Pro.
    static let pageTitle = Font.system(.title2, weight: .semibold).scaled(by: 21.0 / 17)
    static let settingsHeading = Font.system(.title3, weight: .semibold).scaled(by: 18.0 / 15)
    static let sectionTitle = Font.system(.body, design: .default, weight: .medium).scaled(by: 14.0 / 13)
    static let rowTitle = Font.system(.body, design: .default, weight: .medium).scaled(by: 14.0 / 13)
    static let personTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let bodyText = Font.system(.body, design: .default, weight: .regular).scaled(by: 14.0 / 13)
    static let bodyEmphasis = Font.system(.body, design: .default, weight: .medium).scaled(by: 14.0 / 13)
    static let caption = Font.system(.caption, design: .default).scaled(by: 12.0 / 10)
    static let moneyDisplay = Font.system(.largeTitle, design: .default, weight: .medium).scaled(by: 32.0 / 26)

    // The Getting Started guide reads like a document: a large title, roomy
    // headings, and body text a step above the workspace's compact interface text.
    static let documentTitle = Font.system(.largeTitle, weight: .semibold).scaled(by: 34.0 / 26)
    static let documentHeading = Font.system(.title2, weight: .semibold).scaled(by: 23.0 / 17)
    static let documentSubheading = Font.system(.body, design: .default, weight: .semibold).scaled(by: 15.0 / 13)
    static let documentBody = Font.system(.body, design: .default, weight: .regular).scaled(by: 15.0 / 13)
    // Invitation titles: "Setup Tips", "Create New".
    static let displayTitle = Font.system(.title, weight: .semibold).scaled(by: 26.0 / 22)
    static let panelTitle = Font.system(.title, weight: .semibold).scaled(by: 27.0 / 22)
    static let cardTitle = Font.system(.title3, weight: .semibold).scaled(by: 19.0 / 15)

    /// The guide's page inset, wider than a working surface's so the text has margins like a page.
    static let documentInset: CGFloat = 44
}
