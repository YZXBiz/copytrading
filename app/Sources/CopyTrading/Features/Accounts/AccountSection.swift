/// The parts of an account page below its hero and limits, one shown at a time.
enum AccountSection: String, CaseIterable, Identifiable {
    case positions
    case activity

    var id: Self { self }

    var title: String {
        switch self {
        case .positions: "Positions"
        case .activity: "Activity"
        }
    }
}
