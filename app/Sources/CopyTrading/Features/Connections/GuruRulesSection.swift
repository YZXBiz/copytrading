import DesktopCore
import SwiftUI

/// How a guru trades, in the two choices that differ between gurus (ADR-0007): whether a sell
/// refers to the buy price it names or to the whole position, and how many batches make a full
/// position.
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
        } header: {
            SetupSectionHeader(title: "How they trade", detail: "Two things that differ from guru to guru.")
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
