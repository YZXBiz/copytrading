import DesktopCore
import SwiftUI

/// When the guru posts the same call again (ADR-0010). How the guru writes buys, sells, and sizes
/// is read from each post and the playbook, so this is the one choice left per guru.
struct GuruRulesSection: View {
    @Binding var route: TradingRouteDraft

    var body: some View {
        SheetSection(L10n.string("Re-posted calls")) {
            SheetGroup {
                SheetRow(
                    title: L10n.string("Skip re-posted calls"), hint: L10n.string(Self.repostHint(route.repeatWindowMinutes)),
                    labelsControl: true
                ) {
                    Toggle(L10n.string("Skip re-posted calls"), isOn: skipsReposts)
                        .labelsHidden()
                        .compactSwitch()
                }
                if route.repeatWindowMinutes != nil {
                    SheetRow(title: L10n.string("Re-post window (minutes)"), labelsControl: true) {
                        TextField(L10n.string("Re-post window in minutes"), value: repeatMinutes, format: .number)
                            .accessibilityLabel(L10n.string("Re-post window in minutes"))
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .sheetInput(width: DesignTokens.sheetNumberWidth)
                    }
                }
            }
        }
    }

    private static func repostHint(_ minutes: Int?) -> String {
        minutes == nil
            ? "Every post is copied, even a repeat."
            : "Same stock, price, and size counts once. A repeated sell counts once a day."
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
