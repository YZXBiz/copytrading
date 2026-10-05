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
        Section {
            TextField(
                L10n.string("Message"), text: $example.message, prompt: Text(L10n.string("Paste an exact source message")), axis: .vertical
            )
            .accessibilityLabel(L10n.string("Message"))
            .lineLimit(1...4)
            Picker(L10n.string("Expected action"), selection: $example.expectedAction) {
                ForEach(TradingInstructionAction.allCases, id: \.self) { action in
                    Text(Humanize.code(action.rawValue)).tag(action)
                }
            }
            TextField(L10n.string("Expected ticker"), text: $example.expectedSymbol)
            TextField(L10n.string("Expected size"), text: size, prompt: Text(L10n.string("e.g. 1/6, optional")))
                .accessibilityLabel(L10n.string("Expected size"))
        } header: {
            HStack {
                Text(L10n.string("Example %lld", Int64(index + 1)))
                Spacer()
                Button(L10n.string("Remove"), role: .destructive, action: remove)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
    }
}
