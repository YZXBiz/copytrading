import SwiftUI

struct SidebarView<Header: View>: View {
    @Bindable var model: AppModel
    let accountFeature: AccountFeatureModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppModel.ScreenSection.allCases) { section in
                    // Groups are separated by a hairline rather than a heading.
                    if section != AppModel.ScreenSection.allCases.first {
                        Divider()
                            .padding(.vertical, 8)
                            .padding(.horizontal, 9)
                    }
                    ForEach(section.screens) { screen in
                        SidebarRow(
                            title: screen.title,
                            symbol: screen.symbol,
                            identifier: "navigation.\(screen.rawValue)",
                            isSelected: model.selectedScreen == screen,
                            badge: badge(for: screen),
                            progress: progress(for: screen)
                        ) { model.selectedScreen = screen }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
        .navigationTitle(L10n.string("CopyTrading"))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                header()
                SidebarBrandCard(model: model)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusFooter(model: model)
        }
        .background { SidebarPanelBackground() }
    }

    /// Getting Started shows its ring only until the first setup is saved.
    private func progress(for screen: AppModel.Screen) -> Double? {
        guard screen == .gettingStarted, model.savedTradingConfiguration == nil else { return nil }
        return model.setupProgress.fraction
    }

    /// Only posts that wait on the owner earn a count; nothing else competes for attention.
    private func badge(for screen: AppModel.Screen) -> Int {
        guard screen == .activity else { return 0 }
        return accountFeature.activity.filter(\.needsManualReview).count
    }
}
