import DesktopCore
import SwiftUI

/// A guru in the sidebar: their initials and name, over how many calls wait on the owner or how
/// busy today has been.
struct SidebarGuruRow: View {
    let guru: GuruDirectory.Guru
    let model: AppModel
    let accountFeature: AccountFeatureModel

    private var screen: AppModel.Screen { .guru(guru.id) }

    var body: some View {
        let stats = GuruStats(day: accountFeature.guruDays[guru.id], skipped: model.skippedCalls.contains)
        SidebarEntityRow(
            title: guru.name,
            detail: stats.sidebarDetail,
            detailTint: stats.waiting > 0 ? Palette.amber : Palette.tertiaryInk,
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
