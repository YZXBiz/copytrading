import DesktopCore
import SwiftUI
import TipKit

/// One account's equity over a chosen range or day. Hover scrubs any point into the readout and a
/// drag measures the move between two points.
struct EquityChart: View {
    let account: AccountOverview
    let history: EquityHistory?
    let window: EquityHistoryWindow
    let chooseWindow: (EquityHistoryWindow) -> Void
    /// Tall on its own, short while a detail pane shares the page.
    var plotHeight: CGFloat = 176
    @State private var day = Date.now
    @State private var selection = EquitySelection.none
    /// Bumped by Draw It Again to draw the line in once more.
    @State private var drawing = 0
    @FocusState private var isChartFocused: Bool
    /// A click focuses the chart without a ring; Tab or an arrow key brings the ring in.
    @State private var focusCameFromPointer = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.tipGeneration) private var tipGeneration

    /// The broker's curve, carried up to the live balance.
    private var curve: EquityCurve {
        guard let history else { return EquityCurve(combining: []) }
        let balances = account.balance.map { [account.accountID: $0] } ?? [:]
        let extended = LiveEquity.extend([(account.accountID, history)], balances: balances)
        return EquityCurve(combining: extended.map(\.history))
    }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let stats {
                    EquityReadout(title: window.title, range: window.range, curve: curve, stats: stats, selection: selection)
                } else {
                    Text(window.title)
                        .font(DesignTokens.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Spacer(minLength: 12)
                if range == .day {
                    DayPickerButton(day: daySelection)
                        .fixedSize()
                }
                rangeControl
                Button(L10n.string("Draw It Again"), systemImage: "arrow.counterclockwise") { drawing += 1 }
                    .labelStyle(.iconOnly)
                    .buttonStyle(QuietPressButtonStyle())
                    .foregroundStyle(Palette.tertiaryInk)
                    .help(L10n.string("Draw It Again"))
                    .accessibilityIdentifier("chart.redraw")
            }
            if let stats {
                plot(curve: curve, stats: stats)
                    .frame(height: plotHeight)
            } else {
                emptyState
            }
        }
        .onAppear {
            day = window.chosenDay
        }
        .onChange(of: window) { _, chosen in
            selection = .none
            drawing += 1
            if chosen.range == .day { day = chosen.chosenDay }
        }
    }

    private var rangeControl: some View {
        EquityChartPicker(
            options: [.day, .week, .month, .threeMonths], selection: rangeSelection,
            label: "Chart range", identifier: "today.period",
            title: \.title, spokenTitle: \.accessibilityTitle
        )
        .fixedSize()
    }

    @ViewBuilder
    private func plot(curve: EquityCurve, stats: EquityCurveStats) -> some View {
        EquityPlot(curve: curve, stats: stats, range: window.range, selection: $selection)
            .drawsIn(token: drawing)
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
                    .strokeBorder(Palette.ink, lineWidth: contrast == .increased ? 2 : 1.5)
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

    /// A short line while there is no curve, so an idle account doesn't open on a blank band.
    private var emptyState: some View {
        InkEmptyState(
            message: history == nil
                ? L10n.string("The broker's equity curve appears here while copying is on.")
                : L10n.string("The broker has no equity points for this %@.", L10n.string(window.range == .day ? "Day" : "Range"))
        )
        .frame(height: 72, alignment: .bottom)
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
