import SwiftUI

/// Every sheet's frame: what it edits in tracked capitals, its name in the display face and a quiet
/// lede, the content on white, and one bar at the bottom whose only black action is the sheet's
/// answer. No grey panels and no rules; sections open with an ink tick (`SheetSection`).
struct SheetScaffold<Content: View, Leading: View, Actions: View>: View {
    var kind: String?
    let title: String
    var lede: String?
    /// Long sheets scroll; short ones size to their content.
    var scrolls = true
    @ViewBuilder let content: Content
    /// A quiet action at the bar's leading edge, such as Remove.
    @ViewBuilder let leading: Leading
    /// The bar's trailing actions: a quiet secondary, then the one primary (`SheetButtonStyle`).
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            if scrolls {
                ScrollView {
                    page
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                page
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                actions
            }
            .padding(.horizontal, DesignTokens.sheetInset)
            .padding(.vertical, 16)
        }
        .background(Palette.page)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: DesignTokens.sheetSectionSpacing) {
            header
            content
        }
        .padding(.horizontal, DesignTokens.sheetInset)
        .padding(.top, 38)
        .padding(.bottom, DesignTokens.sheetSectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                if let kind {
                    Eyebrow(kind)
                }
                Text(title)
                    .font(DesignTokens.sheetTitle)
                    .tracking(DesignTokens.sheetTitleTracking)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.map { L10n.string("%@ %@", $0, title) } ?? title)
            .accessibilityAddTraits(.isHeader)
            if let lede {
                Text(lede)
                    .font(DesignTokens.lede)
                    .tracking(DesignTokens.ledeTracking)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SheetScaffold where Leading == EmptyView {
    init(
        kind: String? = nil, title: String, lede: String? = nil, scrolls: Bool = true,
        @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            kind: kind, title: title, lede: lede, scrolls: scrolls, content: content, leading: { EmptyView() },
            actions: actions)
    }
}
