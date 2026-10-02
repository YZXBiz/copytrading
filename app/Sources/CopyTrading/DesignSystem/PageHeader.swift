import SwiftUI

/// A compact page title with optional context and actions, aligned to the page content gutter.
struct PageHeader<Leading: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let actions: Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leading
            Text(title)
                .font(DesignTokens.pageTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) { actions }
        }
        .frame(minHeight: 44)
    }
}
