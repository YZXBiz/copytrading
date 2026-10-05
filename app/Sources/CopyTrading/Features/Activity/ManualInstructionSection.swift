import DesktopCore
import SwiftUI

struct ManualInstructionSection: View {
    @Binding var instruction: ManualInstructionDraft
    let index: Int
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        Section {
            Picker(L10n.string("Action"), selection: $instruction.action) {
                Text(L10n.string("Buy")).tag(ManualInstructionAction.buy)
                Text(L10n.string("Reduce owned position")).tag(ManualInstructionAction.reduce)
                Text(L10n.string("Close owned position")).tag(ManualInstructionAction.close)
            }
            TextField(L10n.string("Symbol"), text: $instruction.symbol, prompt: Text(L10n.string("e.g. NVDA")))
                .accessibilityLabel(L10n.string("Symbol"))
            TextField(L10n.string("Source price"), text: $instruction.price, prompt: Text(L10n.string("Price quoted in the message")))
                .accessibilityLabel(L10n.string("Source price"))
            if instruction.action == .buy {
                TextField(L10n.string("Size"), text: size, prompt: Text(L10n.string("e.g. 1/6. Leave empty for the default.")))
                    .accessibilityLabel(L10n.string("Size"))
            } else {
                if instruction.wholePosition {
                    LabeledContent(L10n.string("Sells from"), value: L10n.string("The whole position"))
                } else {
                    TextField(
                        L10n.string("Owned entry price"), text: $instruction.entryPrice,
                        prompt: Text(L10n.string("Entry price of the lot to exit"))
                    )
                    .accessibilityLabel(L10n.string("Owned entry price"))
                }
                if instruction.action == .reduce {
                    TextField(L10n.string("Fraction to reduce"), text: $instruction.fraction, prompt: Text(L10n.string("0 to 1")))
                        .accessibilityLabel(L10n.string("Fraction to reduce"))
                } else {
                    LabeledContent(L10n.string("Fraction"), value: L10n.string("All remaining owned shares"))
                }
            }
        } header: {
            HStack {
                Text(L10n.string("Instruction %lld", Int64(index + 1)))
                Spacer()
                if canRemove {
                    Button(L10n.string("Remove"), role: .destructive, action: remove)
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }
        }
    }

    /// A buy's share as a guru writes it, "1/6", kept as the decimal the engine uses.
    private var size: Binding<String> {
        Binding(
            get: {
                let stored = instruction.fraction.trimmed
                return Decimal(string: stored) == nil ? stored : Humanize.fraction(stored)
            },
            set: { instruction.fraction = ExampleEditorSection.decimal(fromSize: $0) }
        )
    }
}
