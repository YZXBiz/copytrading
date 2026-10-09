/// Which of a guru's posts the timeline shows: all of them, or those that traded, wait on the owner,
/// or were not trades at all.
enum GuruPostFilter: String, CaseIterable, Identifiable {
    case all
    case traded
    case waiting
    case notTraded

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .traded: "Traded"
        case .waiting: "Waiting"
        case .notTraded: "Not traded"
        }
    }

    @MainActor
    func includes(_ entry: GuruFeed.Entry) -> Bool {
        let kinds = entry.accounts.map(\.kind)
        switch self {
        case .all: return true
        case .traded: return kinds.contains(.traded)
        case .waiting: return kinds.contains(.waiting)
        case .notTraded: return !kinds.contains(.traded) && !kinds.contains(.waiting) && !kinds.contains(.working)
        }
    }
}
