import AppLocalizationCore
import SwiftUI

/// One thing a sheet is about, readable at a glance under its title: a service's logo or a symbol,
/// a few words, and a soft tint when the fact has a meaning of its own (paper, live, set).
struct SheetFact: Identifiable {
    var brand: String?
    var symbol = "circle"
    let text: String
    /// A soft fill behind the chip; a neutral well when nil.
    var tint: Color?

    var id: String { text }
}

struct SheetFactChip: View {
    let fact: SheetFact

    var body: some View {
        HStack(spacing: 6) {
            if let brand = fact.brand, let image = BrandIcon.image(named: brand) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: fact.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
            Text(fact.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(fact.tint == nil ? Palette.ink : Color.black.opacity(0.85))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(fact.tint ?? Palette.well, in: .capsule)
        .overlay {
            if fact.tint != nil { Capsule().strokeBorder(Palette.ink.opacity(0.55), lineWidth: 1) }
        }
        .fixedSize()
    }
}
