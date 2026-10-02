/// The combined balance, or each account's change on one scale.
enum EquityChartMode: String, CaseIterable, Identifiable {
    case total
    case accounts

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .total: L10n.string("Total")
        case .accounts: L10n.string("By account")
        }
    }

    @MainActor var accessibilityTitle: String {
        switch self {
        case .total: L10n.string("Combined equity")
        case .accounts: L10n.string("Each account's change")
        }
    }
}
