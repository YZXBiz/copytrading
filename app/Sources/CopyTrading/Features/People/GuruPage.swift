import DesktopCore
import SwiftUI

/// One guru's page: who they are and where their calls go, today's numbers, and every post they
/// made, newest first. Choosing a post opens it beside the feed.
struct GuruPage: View {
    let guruID: String
    let model: AppModel
    let feature: AccountFeatureModel
    @State private var feed: GuruFeed?
    @State private var selectedID: SourceActivity.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guruID: String, model: AppModel, feature: AccountFeatureModel) {
        self.guruID = guruID
        self.model = model
        self.feature = feature
    }

    private var guru: GuruDirectory.Guru? {
        GuruDirectory(model.savedTradingConfiguration).gurus.first { $0.id == guruID }
    }

    private var selectedItem: SourceActivity? {
        feed?.days.lazy.flatMap(\.entries).first { $0.id == selectedID }?.item
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GuruPageHeader(
                        name: guru?.name ?? guruID,
                        destinations: GuruDestinationsText.text(guru, in: model.savedTradingConfiguration),
                        edit: edit)
                    if let feed {
                        GuruStatsStrip(stats: feed.stats)
                            .padding(.top, 32)
                        GuruFeedList(days: feed.days, guruName: guru?.name ?? guruID, selection: $selectedID)
                            .padding(.top, 40)
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.visible)
            .frame(minWidth: 460)
            if let selectedItem {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 1)
                GuruPostDetail(item: selectedItem, model: model, feature: feature, close: closePost)
                    .frame(width: 460)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Palette.page)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28), value: selectedItem == nil)
        .navigationTitle(guru?.name ?? L10n.string("People"))
        .onChange(of: guruID, initial: true) { _, id in
            model.openGuruID = id
            selectedID = nil
            reload()
        }
        .onChange(of: feature.activity) { reload() }
        .onChange(of: model.skippedCalls.skipped) { reload() }
    }

    private func reload() {
        feed = GuruFeed(guruID: guruID, activity: feature.activity, skipped: model.skippedCalls.contains)
    }

    private func edit() {
        model.editGuru(guruID)
    }

    private func closePost() {
        selectedID = nil
    }
}
