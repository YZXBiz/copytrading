import SwiftUI

/// After an import: what was filled, what the setup still needs, and the file's fate. A key file
/// left on the Desktop is the real risk, so moving it to the Trash is the first choice.
struct SetupImportSheet: View {
    let result: SetupImportResult
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(
            kind: L10n.string("Import"),
            title: L10n.string("Setup imported"),
            lede: L10n.string("From %@. Nothing is saved until Connect and Start Copying check it.", result.fileURL.lastPathComponent),
            scrolls: false
        ) {
            list(L10n.string("Filled in"), result.filled, isDone: true)
            if !result.missing.isEmpty {
                list(L10n.string("Still to do"), result.missing, isDone: false)
            }
            Callout(
                L10n.string("The file holds your keys in plain text. Once they're in the Keychain, it's safer in the Trash."),
                tone: .caution)
        } actions: {
            Button(L10n.string("Keep File"), action: close)
                .buttonStyle(SheetButtonStyle())
                .accessibilityIdentifier("setupImport.done")
            Button(L10n.string("Move File to Trash"), action: trash)
                .buttonStyle(SheetButtonStyle(isPrimary: true))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("setupImport.trash")
        }
        .frame(width: 500)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setupImport.sheet")
    }

    /// Each line on a hairline, after a bead: butter in an ink ring once it's filled, an empty ring
    /// while it still waits.
    private func list(_ title: String, _ lines: [String], isDone: Bool) -> some View {
        SheetSection(title) {
            ForEach(lines, id: \.self) { line in
                HStack(spacing: 12) {
                    Circle()
                        .fill(isDone ? Palette.butter : Color.clear)
                        .overlay(Circle().strokeBorder(isDone ? Palette.ink : Palette.tertiaryInk, lineWidth: InkStroke.width))
                        .frame(width: 11, height: 11)
                        .accessibilityHidden(true)
                    Text(line)
                        .foregroundStyle(isDone ? Palette.ink : Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
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
