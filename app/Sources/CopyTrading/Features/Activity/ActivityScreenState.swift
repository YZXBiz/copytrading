import DesktopCore
import Observation

@MainActor
@Observable
final class ActivityScreenState {
    var selectedActivityID: SourceActivity.ID?
    var filter = ActivityFilter.all

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
