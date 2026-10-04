import SwiftUI

/// One account limit in the editor: its name, a plain line on what it does, and its value at the
/// trailing edge, so nobody has to guess what "Maximum per symbol" means.
struct PolicyField<Field: View>: View {
    let title: String
    let hint: String
    /// One worked example behind an "i" beside the name.
    var example: String?
    @ViewBuilder let field: Field

    var body: some View {
        LabeledContent {
            field
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if let example {
                    ExampleMark(title: title, example: example)
                }
            }
            Text(hint)
        }
    }
}
