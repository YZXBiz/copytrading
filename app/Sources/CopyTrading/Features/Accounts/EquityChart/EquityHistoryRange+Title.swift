import DesktopCore

extension EquityHistoryRange {
    /// The short labels brokers use, so the choice reads at a glance.
    var title: String {
        switch self {
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .threeMonths: "3M"
        case .year: "1Y"
        }
    }

    @MainActor var accessibilityTitle: String {
        switch self {
        case .day: L10n.string("One day")
        case .week: L10n.string("One week")
        case .month: L10n.string("One month")
        case .threeMonths: L10n.string("Three months")
        case .year: L10n.string("One year")
        }
    }
}
