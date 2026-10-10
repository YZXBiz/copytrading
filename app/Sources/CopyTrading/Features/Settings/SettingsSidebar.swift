import SwiftUI

/// The sidebar that replaces the main one while Settings is open: the app's name, a
/// line on how it is, and the Settings pages under their tracked-capital groups.
struct SettingsSidebar<Header: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSummaryCard(model: model)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 24)
                ForEach(SettingsPageGroup.allCases) { group in
                    SidebarGroupTitle(title: group.title)
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
                    .padding(.bottom, 18)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .navigationTitle(L10n.string("Settings"))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header()
                SidebarBrandCard(model: model)
            }
        }
        .background { SidebarPanelBackground() }
    }
}
