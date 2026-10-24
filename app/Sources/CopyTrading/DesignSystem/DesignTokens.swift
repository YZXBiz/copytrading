/// Shared layout constants so every screen uses the same rhythm.
import SwiftUI

enum DesignTokens {
    /// A stable inset from the detail column, shared by page headers and their content.
    static let pagePadding: CGFloat = 26
    /// Activity reads like a document inside the wider inspection lane.
    static let readingContentMaxWidth: CGFloat = 720
    static let blockCornerRadius: CGFloat = 10
    static let pageSectionSpacing: CGFloat = 20
    /// The rounded panels Connections and Settings draw their pages on, matching the sidebar's.
    static let panelCornerRadius: CGFloat = 22

    // Titles are set in the display face; everything people read and press stays in SF Pro. The
    // SF Pro roles are fixed point sizes, never `Font.scaled(by:)`: a vertical-axis text field
    // measures a scaled font at one size and draws it at another, so it shows only some of its
    // lines, and any of these roles can end up on an editable field.
    /// A screen's name at the top of its page, as large as an account's name.
    static let pageTitle = DisplayFont.font(size: 42, weight: .medium, relativeTo: .largeTitle)
    /// An account's or guru's page: the name, then the balance under it.
    /// An account or guru's name: large and regular, tracked tight, as on a studio site.
    static let entityTitle = DisplayFont.font(size: 42, weight: .medium, relativeTo: .largeTitle)
    static let entityTitleTracking: CGFloat = 0.2
    /// The balance is the page's one big figure: light enough to read as type, not a badge.
    static let balanceDisplay = DisplayFont.font(size: 68, weight: .regular, relativeTo: .largeTitle)
    static let balanceTracking: CGFloat = -0.5
    /// The balance's cents, stepped down beside it in grey.
    static let balanceCents = DisplayFont.font(size: 34, weight: .regular, relativeTo: .title)
    static let statValue = Font.system(size: 14, weight: .semibold)
    static let listHeading = DisplayFont.font(size: 26, weight: .medium, relativeTo: .title2)
    static let listHeadingTracking: CGFloat = 0.2
    /// A small grey label in sentence case over or beside what it names: a column, a figure, a
    /// group. Never capitals spaced wide.
    static let label = Font.system(size: 12, weight: .medium)
    /// A quiet line under a big name, spaced a little wide so it reads as a caption to the title.
    static let lede = Font.system(size: 14)
    static let ledeTracking: CGFloat = 0.8
    static let feedTitle = Font.system(.body, weight: .semibold)
    /// The sidebar's account and guru rows.
    static let sidebarTitle = Font.system(.body, weight: .medium)
    static let sidebarDetail = Font.system(size: 11)
    /// A group of settings or a setup step: the display face, a size under a list heading.
    static let settingsHeading = DisplayFont.font(size: 22, weight: .medium, relativeTo: .title3)
    static let sectionTitle = Font.system(size: 14, weight: .medium)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let bodyText = Font.system(size: 14, weight: .regular)
    static let bodyEmphasis = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12)

    // The Getting Started guide reads like a studio site's front page: a hero headline, display
    // headings, and body text a step above the workspace's compact interface text.
    static let documentTitle = DisplayFont.font(size: 64, weight: .regular, relativeTo: .largeTitle)
    static let documentTitleTracking: CGFloat = -0.4
    static let documentHeading = DisplayFont.font(size: 26, weight: .medium, relativeTo: .title2)
    static let documentSubheading = Font.system(size: 15, weight: .semibold)
    static let documentBody = Font.system(size: 15, weight: .regular)
    /// A closing section's title, such as "Setup Tips".
    static let displayTitle = DisplayFont.font(size: 26, weight: .medium, relativeTo: .title2)
    /// A panel's or a quiet hero's title: the assistant's welcome, the engine, the lock screen.
    static let panelTitle = DisplayFont.font(size: 30, weight: .medium, relativeTo: .title)
    /// A titled item inside a page: a tip, a proposal, a step of a post's journey.
    static let cardTitle = DisplayFont.font(size: 20, weight: .medium, relativeTo: .title3)

    // Activity's text: prose, then labels and IDs; numbers use monospaced digits wherever they line up.
    static let activityBody = Font.system(.body)
    static let activityMeta = Font.system(size: 12)
    static let activityIdentifier = Font.system(size: 12, design: .monospaced)
    /// The label column of Technical details' key/value rows.
    static let factLabelWidth: CGFloat = 116

    /// The guide's page inset, wider than a working surface's so the text has margins like a page.
    static let documentInset: CGFloat = 44
}
