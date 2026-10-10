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
        let posts = accountFeature.activity.filter { $0.guruID == guru.id }
        let waiting = posts.filter { ActivityFilter.waiting.includes($0, skipped: model.skippedCalls) }.count
        let today = posts.filter(\.isToday).count
        SidebarEntityRow(
            title: guru.name,
            detail: detail(waiting: waiting, today: today),
            detailTint: waiting > 0 ? Palette.amber : Palette.tertiaryInk,
            identifier: screen.identifier,
            isSelected: model.selectedScreen == screen,
            select: select
        ) {
            GuruMonogram(name: guru.name, size: 20)
        }
    }

    private func detail(waiting: Int, today: Int) -> String {
        if waiting > 0 { return L10n.string("%lld need you", Int64(waiting)) }
        if today > 0 { return L10n.string("%@ today", Humanize.count(today, "post")) }
        return L10n.string("Quiet today")
    }

    private func select() {
        model.selectedScreen = screen
    }
}
