import DesktopCore
import SwiftUI
import TipKit

/// The copied accounts' equity over a chosen range or day. Hover scrubs any point into the
/// headline, a drag measures the move between two points, and the accounts can be compared.
struct EquityChart: View {
    let accounts: [AccountOverview]
    let histories: [String: EquityHistory]
    let window: EquityHistoryWindow
    let chooseWindow: (EquityHistoryWindow) -> Void
    @State private var day = Date.now
    @State private var mode = EquityChartMode.total
    @State private var selection = EquitySelection.none
    @State private var showsRangeDetails = false
    @FocusState private var isChartFocused: Bool
    /// A click focuses the chart without a ring; Tab or an arrow key brings the ring in.
    @State private var focusCameFromPointer = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.tipGeneration) private var tipGeneration

    private static let plotHeight: CGFloat = 200

    /// The active accounts' broker curves, each carried up to its live balance.
    private var activeHistories: [(accountID: String, history: EquityHistory)] {
        let active = accounts.filter(\.activeConfiguration)
        let recorded = active.compactMap { account in
            histories[account.accountID].map { (account.accountID, $0) }
        }
        let balances = Dictionary(
            uniqueKeysWithValues: active.compactMap { account in
                account.balance.map { (account.accountID, $0) }
            })
        return LiveEquity.extend(recorded, balances: balances)
    }

    private var curve: EquityCurve { EquityCurve(combining: activeHistories.map(\.history)) }
    private var range: EquityHistoryRange { window.range }

    /// The loaded window owns the selection. An unavailable engine must not leave a selected
    /// "1W" button above an unchanged day curve.
    private var rangeSelection: Binding<EquityHistoryRange> {
        Binding(get: { window.range }, set: { choose(EquityHistoryWindow(range: $0)) })
    }

    private var daySelection: Binding<Date> {
        Binding(
            get: { window.chosenDay },
            set: { chosen in
                day = chosen
                choose(.day(chosen))
            })
    }

    var body: some View {
        let curve = self.curve
        let stats = curve.points.count >= 2 ? curve.stats : nil
        let series = mode == .accounts ? AccountSeries.make(from: activeHistories) : []
        let comparable = activeHistories.count >= 2
        VStack(alignment: .leading, spacing: 14) {
            controls(comparable: comparable)
            headline(curve: curve, stats: stats, series: series)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let stats {
                plot(curve: curve, stats: stats, series: series)
                    .frame(height: Self.plotHeight)
            } else {
                emptyState
            }
            DisclosureGroup(L10n.string("Range details"), isExpanded: $showsRangeDetails) {
                EquityStatsRow(stats: stats, hasPreviousClose: curve.baseline != nil)
            }
            .font(DesignTokens.caption)
            .foregroundStyle(Palette.secondaryInk)
            .tint(Palette.secondaryInk)
            .accessibilityIdentifier("today.rangeDetails")
        }
        .onAppear {
            day = window.chosenDay
        }
        .onChange(of: window) { _, chosen in
            selection = .none
            if chosen.range == .day { day = chosen.chosenDay }
        }
        .onChange(of: mode) { _, _ in selection = .none }
        .onChange(of: comparable) { _, canCompare in if !canCompare { mode = .total } }
    }

    @ViewBuilder
    private func headline(curve: EquityCurve, stats: EquityCurveStats?, series: [AccountSeries]) -> some View {
        if let stats {
            EquityReadout(
                title: window.title, range: window.range, mode: mode,
                curve: curve, stats: stats, accounts: series, selection: selection
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(window.title)
                    .font(DesignTokens.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.string("No equity to show"))
                    .font(.system(.title2, design: .default, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(minHeight: 28, alignment: .leading)
            }
        }
    }

    private func controls(comparable: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                viewAndDayControls(comparable: comparable)
                Spacer(minLength: 8)
                rangeControl
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) { viewAndDayControls(comparable: comparable) }
                rangeControl
            }
        }
    }

    @ViewBuilder
    private func viewAndDayControls(comparable: Bool) -> some View {
        if comparable {
            EquityChartPicker(
                options: EquityChartMode.allCases, selection: $mode,
                label: "Chart view", identifier: "today.chartMode",
                title: \.title, spokenTitle: \.accessibilityTitle
            )
        }
        if range == .day {
            DayPickerButton(day: daySelection)
                .fixedSize()
        }
    }

    private var rangeControl: some View {
        EquityChartPicker(
            options: EquityHistoryRange.allCases, selection: rangeSelection,
            label: "Chart range", identifier: "today.period",
            title: \.title, spokenTitle: \.accessibilityTitle
        )
        .fixedSize()
    }

    @ViewBuilder
    private func plot(curve: EquityCurve, stats: EquityCurveStats, series: [AccountSeries]) -> some View {
        Group {
            switch mode {
            case .total:
                EquityPlot(curve: curve, stats: stats, range: window.range, selection: $selection)
            case .accounts:
                AccountComparisonPlot(series: series, range: window.range, selection: $selection)
            }
        }
        .popoverTip(MeasureChartTip(generation: tipGeneration), arrowEdge: .bottom)
        .task {
            await MeasureChartTip.chartViewed.donate()
        }
        .onChange(of: selection) { _, chosen in
            if case .span(_, _, settled: true) = chosen {
                MeasureChartTip(generation: tipGeneration).invalidate(reason: .actionPerformed)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(window.title)
        .accessibilityValue(summary(stats))
        .accessibilityHint(L10n.string("Use the left and right arrow keys to read recorded points."))
        .focusable()
        .focused($isChartFocused)
        .focusEffectDisabled()
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in focusCameFromPointer = true })
        .onChange(of: isChartFocused) { _, focused in
            if !focused { focusCameFromPointer = false }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Palette.accent, lineWidth: contrast == .increased ? 2 : 1.5)
                .opacity(isChartFocused && !focusCameFromPointer ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onMoveCommand { direction in
            focusCameFromPointer = false
            switch direction {
            case .left: step(through: curve.points, forward: false)
            case .right: step(through: curve.points, forward: true)
            default: break
            }
        }
        .onExitCommand {
            focusCameFromPointer = false
            selection = .none
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(through: curve.points, forward: true)
            case .decrement: step(through: curve.points, forward: false)
            @unknown default: break
            }
        }
    }

    /// Kept at the plot's height so data arriving does not move the page.
    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(
                activeHistories.isEmpty
                    ? L10n.string("The broker's equity curve appears here while copying is on.")
                    : L10n.string("The broker has no equity points for this %@.", L10n.string(window.range == .day ? "Day" : "Range"))
            )
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: Self.plotHeight)
        .background(Palette.group, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
    }

    private func choose(_ chosen: EquityHistoryWindow) {
        let next = chosen.range == .day ? EquityHistoryWindow.day(day) : chosen
        if next != window { chooseWindow(next) }
    }

    /// Moves the keyboard cursor to the next or previous recorded point.
    private func step(through points: [EquityCurvePoint], forward: Bool) {
        guard !points.isEmpty else { return }
        let current = selection.point.flatMap { date in points.firstIndex { $0.at >= date } }
        let index = current ?? (forward ? -1 : points.count)
        selection = .point(points[min(max(index + (forward ? 1 : -1), 0), points.count - 1)].at)
    }

    @MainActor private func summary(_ stats: EquityCurveStats) -> String {
        let change = stats.change.formatted(.currency(code: "USD").sign(strategy: .always()))
        return L10n.string(
            "From %@ to %@, %@. High %@, low %@.",
            stats.reference.formatted(.currency(code: "USD")), stats.last.value.formatted(.currency(code: "USD")),
            change, stats.high.value.formatted(.currency(code: "USD")), stats.low.value.formatted(.currency(code: "USD"))
        )
    }
}
