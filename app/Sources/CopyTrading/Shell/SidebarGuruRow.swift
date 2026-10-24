import DesktopCore
import SwiftUI

/// A guru in the sidebar: their initials and name, and an amber count of the calls waiting on the
/// owner.
struct SidebarGuruRow: View {
    let guru: GuruDirectory.Guru
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var screen: AppModel.Screen { .guru(guru.id) }

    var body: some View {
        let stats = GuruStats(
            day: accountFeature.guruDays[guru.id], skipped: model.skippedCalls.contains,
            isRead: accountFeature.lastUpdatedAt != nil)
        SidebarEntityRow(
            title: guru.name,
            spoken: stats.waiting > 0 ? L10n.string("%lld waiting", Int64(stats.waiting)) : "",
            count: stats.waiting,
            identifier: screen.identifier,
            isSelected: model.selectedScreen == screen,
            select: select
        ) {
            GuruMonogram(name: guru.name, size: 20)
        }
    }

    private func select() {
        model.selectedScreen = screen
    }
}
