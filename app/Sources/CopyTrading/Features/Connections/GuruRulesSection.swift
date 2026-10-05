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
                Text(L10n.string("“First batch”, “second batch”: each is an equal part of the full position."))
            }
            .compactSwitch()
            if let batches = route.batches {
                Stepper(value: batchCount, in: 2...20) {
                    Text(L10n.string("%@ batches make a full position", "\(batches)"))
                }
            }
        } header: {
            SetupSectionHeader(title: "How they trade", detail: "The two habits that differ most between gurus.")
        }
    }

    private static func sellsHint(_ rule: TradingSellsReferTo) -> String {
        switch rule {
        case .buyPrice:
            "Each buy is its own lot, and a sell names the one it sells, like “sell half of the 39.5”."
        case .wholePosition:
            "Every buy of a stock is one position, and a sell like “out of RCL” sells from all of it."
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
