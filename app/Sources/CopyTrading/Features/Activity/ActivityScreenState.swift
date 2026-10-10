import DesktopCore
import Observation

@MainActor
@Observable
final class ActivityScreenState {
    var selectedActivityID: SourceActivity.ID?
    var filter = ActivityFilter.all
    /// The one account Activity shows, or every account; kept for this window.
    var accountID: String?

    /// A post belongs to the chosen account when it reached it; with every account chosen, all posts show.
    func includes(_ item: SourceActivity) -> Bool {
        guard let accountID else { return true }
        return item.destinations.contains { $0.accountID == accountID }
    }

    func applyFilter(_ filter: ActivityFilter, visibleIDs: [SourceActivity.ID]) {
        self.filter = filter
        reconcileSelection(visibleIDs: visibleIDs)
    }

    func reconcileSelection(visibleIDs: [SourceActivity.ID]) {
        guard selectedActivityID.map(visibleIDs.contains) != true else { return }
        selectedActivityID = visibleIDs.first
    }

    func focusActivity(_ id: SourceActivity.ID) {
        filter = .all
        selectedActivityID = id
    }
}
