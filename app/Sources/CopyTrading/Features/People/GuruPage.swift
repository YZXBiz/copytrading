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
                        pendingNote: model.guruPendingNote(guruID),
                        edit: edit,
                        review: review)
                    if let feed {
                        GuruStatsStrip(
                            stats: GuruStats(
                                day: feature.guruDays[guruID], waiting: feed.waitingCount,
                                isRead: feature.lastUpdatedAt != nil)
                        )
                        .padding(.top, 36)
                        GuruHoldingsLine(
                            holdings: GuruHoldings(
                                guruID: guruID, accounts: feature.accounts,
                                setUpAccountIDs: Set(model.savedTradingConfiguration?.accounts.map(\.id) ?? []))
                        )
                        .padding(.top, 20)
                        GuruFeedList(
                            days: feed.days, isRead: feature.guruPosts[guruID] != nil,
                            error: feature.errors["guru:\(guruID)"],
                            selection: $selectedID,
                            loadMore: olderPosts
                        )
                        .padding(.top, 56)
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.visible)
            .frame(minWidth: 460)
            if let selectedItem {
                // The post sits on the canvas grey beside the white page: tone parts them, not a rule.
                PostDetailPane(item: selectedItem, model: model, feature: feature, close: closePost)
                    .frame(width: 460)
                    .background(Palette.canvas)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Palette.page)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28), value: selectedItem == nil)
        .navigationTitle(guru?.name ?? L10n.string("People"))
        .onChange(of: guruID, initial: true) {
            selectedID = nil
            reload()
        }
        .task(id: guruID) {
            if feature.guruPosts[guruID] == nil {
                await feature.loadGuruPosts(guruID: guruID, using: model.accountActions())
            }
        }
        .onChange(of: feature.activity) { reload() }
        .onChange(of: feature.guruPosts[guruID]) { reload() }
        .onChange(of: feature.guruDays[guruID]) { reload() }
        .onChange(of: model.skippedCalls.skipped) { reload() }
    }

    /// The guru's own pages, each post in its freshest version: the newest posts of every guru
    /// are re-read every second while one is in flight, a guru's pages only every 15 s.
    private func reload() {
        let fresh = Set(feature.activity.map(\.id))
        let posts = feature.activity + (feature.guruPosts[guruID] ?? []).filter { !fresh.contains($0.id) }
        feed = GuruFeed(
            guruID: guruID, activity: posts, day: feature.guruDays[guruID],
            skipped: model.skippedCalls.contains)
    }

    /// Reads the next older page, while the guru has older posts.
    private var olderPosts: (() -> Void)? {
        guard feature.guruPostCursors[guruID] != nil else { return nil }
        return { [feature, model, guruID] in
            Task { await feature.loadGuruPosts(guruID: guruID, more: true, using: model.accountActions()) }
        }
    }

    private func edit() {
        model.editGuru(guruID)
    }

    private func review() {
        model.selectedScreen = .connections
        model.editGuru(guruID)
    }

    private func closePost() {
        selectedID = nil
    }
}
