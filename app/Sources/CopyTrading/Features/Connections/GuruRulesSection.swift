import DesktopCore
import SwiftUI

/// When the guru posts the same call again (ADR-0010). How the guru writes buys, sells, and sizes
/// is read from each post and the playbook, so this is the one choice left per guru.
struct GuruRulesSection: View {
    @Binding var route: TradingRouteDraft

    var body: some View {
        Section {
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
            SetupSectionHeader(title: "Re-posted calls", detail: "When the guru posts the same call again.")
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
}
