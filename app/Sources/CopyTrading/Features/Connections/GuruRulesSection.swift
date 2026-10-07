import DesktopCore
import SwiftUI

/// How a guru trades, in the choices that differ between gurus (ADR-0007): whether a sell refers
/// to the buy price it names or to the whole position, how many batches make a full position, and
/// whether a re-posted call is skipped.
struct GuruRulesSection: View {
    @Binding var route: TradingRouteDraft

    var body: some View {
        Section {
            Picker(selection: $route.sellsReferTo) {
                Text(L10n.string("The buy price")).tag(TradingSellsReferTo.buyPrice)
                Text(L10n.string("The whole position")).tag(TradingSellsReferTo.wholePosition)
            } label: {
                Text(L10n.string("A sell refers to"))
                Text(L10n.string(Self.sellsHint(route.sellsReferTo)))
            }
            .pickerStyle(.segmented)
            Toggle(isOn: buysInBatches) {
                Text(L10n.string("Buys in batches"))
                Text(L10n.string("“First batch”, “second batch”: each batch buys an equal part of the full position."))
            }
            .compactSwitch()
            .accessibilityLabel(Text(L10n.string("Buys in batches")))
            if let batches = route.batches {
                Stepper(value: batchCount, in: 2...20) {
                    Text(L10n.string("%@ batches make a full position", "\(batches)"))
                }
            }
            Toggle(isOn: skipsReposts) {
                Text(L10n.string("Skip re-posted calls"))
                Text(L10n.string(Self.repostHint(route.repeatWindowMinutes)))
            }
            .compactSwitch()
            .accessibilityLabel(Text(L10n.string("Skip re-posted calls")))
            if route.repeatWindowMinutes != nil {
                LabeledContent(L10n.string("Counts as a re-post within")) {
                    HStack(spacing: 6) {
                        TextField(L10n.string("Minutes"), value: repeatMinutes, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                            .accessibilityLabel(Text(L10n.string("Minutes")))
                        Text(L10n.string("minutes"))
                            .foregroundStyle(.secondary)
                        Stepper(L10n.string("Minutes"), value: repeatMinutes, in: TradingRouteConfiguration.repeatWindowRange)
                            .labelsHidden()
                    }
                }
            }
        } header: {
            SetupSectionHeader(title: "How they trade", detail: "Three things that differ from guru to guru.")
        }
    }

    private static func sellsHint(_ rule: TradingSellsReferTo) -> String {
        switch rule {
        case .buyPrice:
            "Each buy is kept separate. A sell says which buy, like “sell half of the 39.5”."
        case .wholePosition:
            "All buys of a stock count as one. A sell like “out of RCL” sells from all of them."
        }
    }

    private static func repostHint(_ minutes: Int?) -> String {
        minutes == nil
            ? "Every post is copied, even one that repeats an earlier call."
            : "The same call again (same stock, price, and size) counts once. A repeated sell counts once all day."
    }

    private var skipsReposts: Binding<Bool> {
        Binding(
            get: { route.repeatWindowMinutes != nil },
            set: {
                route.repeatWindowMinutes =
                    $0 ? (route.repeatWindowMinutes ?? TradingRouteConfiguration.defaultRepeatWindowMinutes) : nil
            }
        )
    }

    private var repeatMinutes: Binding<Int> {
        Binding(
            get: { route.repeatWindowMinutes ?? TradingRouteConfiguration.defaultRepeatWindowMinutes },
            // A typed value outside a minute to a day is held to the nearest end.
            set: {
                let range = TradingRouteConfiguration.repeatWindowRange
                route.repeatWindowMinutes = min(max($0, range.lowerBound), range.upperBound)
            }
        )
    }

    private var buysInBatches: Binding<Bool> {
        Binding(
            get: { route.batches != nil },
            set: { route.batches = $0 ? (route.batches ?? 3) : nil }
        )
    }

    private var batchCount: Binding<Int> {
        Binding(get: { route.batches ?? 3 }, set: { route.batches = $0 })
    }
}
