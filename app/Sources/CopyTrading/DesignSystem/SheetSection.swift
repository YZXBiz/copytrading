import SwiftUI

/// One part of a sheet: its title in the display face, as the Settings pages head their groups,
/// with an optional quiet line under it and an accessory at the trailing edge, then its rows, then
/// a footnote. Space and the title's weight set sections apart; no rule or mark runs between them.
struct SheetSection<Content: View, Accessory: View, Footer: View>: View {
    let title: String
    let detail: String?
    let content: Content
    let accessory: Accessory
    let footer: Footer

    init(
        _ title: String, detail: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
        self.accessory = accessory()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(DesignTokens.cardTitle)
                        .tracking(DesignTokens.listHeadingTracking)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(DesignTokens.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(detail.map { L10n.string("%@, %@", title, $0) } ?? title)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                accessory
            }
            .padding(.top, 14)
            .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .font(DesignTokens.bodyText)
            .foregroundStyle(Palette.ink)
            footerView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var footerView: some View {
        if Footer.self != EmptyView.self {
            footer
                .font(DesignTokens.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }
}

extension SheetSection where Accessory == EmptyView, Footer == EmptyView {
    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, detail: detail, content: content, accessory: { EmptyView() }, footer: { EmptyView() })
    }
}

extension SheetSection where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(title, detail: detail, content: content, accessory: { EmptyView() }, footer: footer)
    }
}

extension SheetSection where Footer == EmptyView {
    init(
        _ title: String, detail: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title, detail: detail, content: content, accessory: accessory, footer: { EmptyView() })
    }
}
