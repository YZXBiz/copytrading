/// The parts of an account page below its hero, one shown at a time.
enum AccountSection: String, CaseIterable, Identifiable {
    case positions
    case activity
    case limits

    var id: Self { self }

    var title: String {
        switch self {
        case .positions: "Positions"
        case .activity: "Activity"
        case .limits: "Limits"
        }
    }
}
