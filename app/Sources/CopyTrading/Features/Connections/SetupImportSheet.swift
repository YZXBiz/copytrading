import SwiftUI

/// After an import: what was filled, what the setup still needs, and the file's fate. A key file
/// left on the Desktop is the real risk, so moving it to the Trash is the first choice.
struct SetupImportSheet: View {
    let result: SetupImportResult
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Setup imported"))
                    .font(.system(.title3, design: .serif, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(L10n.string("From %@. Nothing is saved until Connect and Start Copying check it.", result.fileURL.lastPathComponent))
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            list(L10n.string("Filled in"), result.filled, symbol: "checkmark.circle.fill", tint: .green)
            if !result.missing.isEmpty {
                list(L10n.string("Still to do"), result.missing, symbol: "circle.dashed", tint: Palette.secondaryInk)
            }
            Callout(
                L10n.string("The file holds your keys in plain text. Once they're in the Keychain, it's safer in the Trash."),
                tone: .caution)
            HStack {
                Spacer()
                Button(L10n.string("Keep File"), action: close)
                    .accessibilityIdentifier("setupImport.done")
                Button(L10n.string("Move File to Trash"), action: trash)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("setupImport.trash")
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setupImport.sheet")
    }

    private func list(_ title: String, _ lines: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.ink)
            ForEach(lines, id: \.self) { line in
                Label {
                    Text(line).foregroundStyle(Palette.ink)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
            }
        }
    }

    private func trash() {
        model.trashImportedFile()
        dismiss()
    }

    private func close() {
        model.setupImportResult = nil
        dismiss()
    }
}
