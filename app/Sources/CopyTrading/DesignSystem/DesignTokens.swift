/// Shared layout constants so every screen uses the same rhythm.
import SwiftUI

enum DesignTokens {
    /// A stable inset from the detail column, shared by page headers and their content.
    static let pagePadding: CGFloat = 26
    static let todayContentMaxWidth: CGFloat = 1_040
    static let todayTimelineMinWidth: CGFloat = 320
    static let todayLimitsWidth: CGFloat = 248
    static let workingSurfacePadding: CGFloat = 24
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
    /// An account's or guru's page: the name, then the balance under it.
    /// An account or guru's name: large and regular, tracked tight, as on a studio site.
    static let entityTitle = DisplayFont.font(size: 42, weight: .medium, relativeTo: .largeTitle)
    static let entityTitleTracking: CGFloat = 0.2
    /// The balance is the page's one big figure: light enough to read as type, not a badge.
    static let balanceDisplay = DisplayFont.font(size: 68, weight: .regular, relativeTo: .largeTitle)
    static let balanceTracking: CGFloat = -0.5
    static let statValue = Font.system(.body, weight: .semibold).scaled(by: 14.0 / 13)
    static let listHeading = DisplayFont.font(size: 26, weight: .medium, relativeTo: .title2)
    static let listHeadingTracking: CGFloat = 0.2
    /// Small bold capitals spaced wide, like a studio site's navigation: labels, never sentences.
    static let eyebrow = Font.system(.caption, weight: .bold).scaled(by: 11.0 / 10)
    static let eyebrowTracking: CGFloat = 1.4
    /// A quiet line under a big name, spaced a little wide so it reads as a caption to the title.
    static let lede = Font.system(.body).scaled(by: 14.0 / 13)
    static let ledeTracking: CGFloat = 0.8
    static let feedTitle = Font.system(.body, weight: .semibold)
    /// The sidebar's account and guru rows, and the small capitals over each group.
    static let sidebarTitle = Font.system(.body, weight: .medium)
    static let sidebarDetail = Font.system(.caption).scaled(by: 11.0 / 10)
    static let sidebarGroup = Font.system(.caption, weight: .semibold).scaled(by: 10.5 / 10)
    static let settingsHeading = Font.system(.title3, weight: .semibold).scaled(by: 18.0 / 15)
    static let sectionTitle = Font.system(.body, design: .default, weight: .medium).scaled(by: 14.0 / 13)
    static let rowTitle = Font.system(.body, design: .default, weight: .medium).scaled(by: 14.0 / 13)
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

    // Activity's one scale: the takeaway, the guru's words, prose, then labels and IDs. A row never
    // mixes two of these; numbers use monospaced digits wherever they line up.
    static let activityHeadline = Font.system(.body, weight: .semibold).scaled(by: 17.0 / 13)
    static let activityOutcome = Font.system(.body, weight: .semibold).scaled(by: 15.0 / 13)
    static let activityQuote = Font.system(.body).scaled(by: 15.0 / 13)
    static let activityBody = Font.system(.body)
    static let activityValue = Font.system(.body, weight: .medium)
    static let activityMeta = Font.system(.caption).scaled(by: 12.0 / 10)
    static let activitySection = Font.system(.caption, weight: .semibold).scaled(by: 11.0 / 10)
    static let activityIdentifier = Font.system(.caption, design: .monospaced).scaled(by: 12.0 / 10)
    /// The label column of Technical details' key/value rows.
    static let factLabelWidth: CGFloat = 116

    /// The guide's page inset, wider than a working surface's so the text has margins like a page.
    static let documentInset: CGFloat = 44
}
