import DesktopCore
import SwiftUI

struct ExampleEditorSection: View {
    @Binding var example: TradingProfileExampleDraft
    let index: Int
    let remove: () -> Void

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
            TextField(L10n.string("Expected fraction"), text: $example.expectedFraction, prompt: Text(L10n.string("0 to 1, optional")))
                .accessibilityLabel(L10n.string("Expected fraction"))
            if !example.expectedFraction.trimmed.isEmpty, Decimal(string: example.expectedFraction.trimmed) != nil {
                LabeledContent(L10n.string("Reads as"), value: Humanize.fraction(example.expectedFraction.trimmed))
                    .foregroundStyle(.secondary)
            }
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
