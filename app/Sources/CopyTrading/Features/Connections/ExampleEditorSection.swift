import DesktopCore
import SwiftUI

struct ExampleEditorSection: View {
    @Binding var example: TradingProfileExampleDraft
    let index: Int
    let remove: () -> Void

    /// The size as the guru writes it, "1/6", kept as the decimal the reader is checked against.
    private var size: Binding<String> {
        Binding(
            get: {
                let stored = example.expectedFraction.trimmed
                return Decimal(string: stored) == nil ? stored : Humanize.fraction(stored)
            },
            set: { example.expectedFraction = Self.decimal(fromSize: $0) }
        )
    }

    /// "1/6" becomes 1/6 as a decimal; a decimal or anything half-typed stays as typed.
    static func decimal(fromSize text: String) -> String {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let numerator = Decimal(string: parts[0]), let denominator = Decimal(string: parts[1]),
            denominator > 0
        else { return text }
        return "\(numerator / denominator)"
    }

    var body: some View {
        SheetSection(L10n.string("Example %lld", Int64(index + 1))) {
            SheetField(title: L10n.string("Message")) {
                TextField(
                    L10n.string("Message"), text: $example.message,
                    prompt: Text(L10n.string("Paste an exact source message")).foregroundStyle(Palette.tertiaryInk),
                    axis: .vertical
                )
                .accessibilityLabel(L10n.string("Message"))
                .lineLimit(1...4)
            }
            SheetRow(title: L10n.string("Expected action")) {
                SheetChoices(
                    label: L10n.string("Expected action"),
                    choices: TradingInstructionAction.allCases.map { ($0, Humanize.code($0.rawValue)) },
                    selection: $example.expectedAction, identifier: "example.action")
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                GridRow {
                    SheetField(title: L10n.string("Expected ticker")) {
                        TextField(L10n.string("Expected ticker"), text: $example.expectedSymbol)
                            .accessibilityLabel(L10n.string("Expected ticker"))
                    }
                    SheetField(title: L10n.string("Expected size")) {
                        TextField(
                            L10n.string("Expected size"), text: size,
                            prompt: Text(L10n.string("e.g. 1/6, optional")).foregroundStyle(Palette.tertiaryInk)
                        )
                        .accessibilityLabel(L10n.string("Expected size"))
                    }
                }
                GridRow {
                    SheetField(title: priceTitle) {
                        TextField(
                            priceTitle, text: $example.expectedPrice,
                            prompt: Text(L10n.string("e.g. %@, optional", "39.5")).foregroundStyle(Palette.tertiaryInk)
                        )
                        .accessibilityLabel(priceTitle)
                    }
                    if example.expectedAction != .buy {
                        SheetField(title: L10n.string("Sells from the buy at")) {
                            TextField(
                                L10n.string("Sells from the buy at"), text: $example.expectedBuyPrice,
                                prompt: Text(L10n.string("e.g. %@, or empty for every buy", "39.5")).foregroundStyle(Palette.tertiaryInk)
                            )
                            .accessibilityLabel(L10n.string("Sells from the buy at"))
                        }
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        } accessory: {
            Button(L10n.string("Remove"), role: .destructive, action: remove)
                .buttonStyle(SheetQuietButtonStyle(isDestructive: true))
                .font(DesignTokens.caption)
        }
    }

    private var priceTitle: String {
        example.expectedAction == .buy ? L10n.string("Expected buy price") : L10n.string("Expected sell price")
    }
}
