import SwiftUI

/// The sidebar that replaces the main one while Settings is open: the app's icon and name, a status
/// card, and the Settings pages in their groups.
struct SettingsSidebar<Header: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSidebarHero(model: model)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                SettingsSummaryCard(model: model)
                    .padding(.bottom, 26)
                ForEach(SettingsPageGroup.allCases) { group in
                    Text(L10n.string(group.title))
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 9)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 2) {
                        ForEach(group.pages) { page in
                            SidebarRow(
                                title: L10n.string(page.title),
                                symbol: page.symbol,
                                identifier: "settings.page.\(page.rawValue)",
                                isSelected: model.settingsPage == page
                            ) { model.show(page) }
                        }
                    }
                    .padding(.bottom, 22)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .navigationTitle(L10n.string("Settings"))
        .safeAreaInset(edge: .top, spacing: 0) {
            header()
        }
        .background { SidebarPanelBackground() }
    }
}
