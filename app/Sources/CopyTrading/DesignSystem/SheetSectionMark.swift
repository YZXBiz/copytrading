import SwiftUI

/// How far a sheet's section has come, beside its title, so the eye can run down a sheet and see
/// what is left: a sage "Set" once it is filled in, a butter "Needs you" while it waits on the
/// owner. Each is a riso fill inside an ink outline with its own symbol, never colour alone.
enum SheetSectionMark: Equatable {
    case done
    case needsYou

    @MainActor var label: String {
        switch self {
        case .done: L10n.string("Set")
        case .needsYou: L10n.string("Needs you")
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark"
        case .needsYou: "arrow.right"
        }
    }

    var fill: Color {
        switch self {
        case .done: Palette.sage
        case .needsYou: Palette.butter
        }
    }
}

struct SheetSectionMarkView: View {
    let mark: SheetSectionMark

    var body: some View {
        Label(mark.label, systemImage: mark.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(mark.fill, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.7), lineWidth: 1))
            .fixedSize()
    }
}
