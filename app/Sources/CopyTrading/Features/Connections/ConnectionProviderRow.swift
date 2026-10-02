import DesktopCore
import SwiftUI

/// The interpreter's provider as the first row of its panel: a small grey label over the name,
/// with an up-down chevron, and the whole row opens the grouped list.
struct ConnectionProviderRow: View {
    @Binding var provider: TradingProviderName

    var body: some View {
        Menu {
            Picker(L10n.string("Provider"), selection: $provider) {
                ForEach(ProviderGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.providers, id: \.self) { name in
                            Text(L10n.string(name.title)).tag(name)
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Provider"))
                        .font(DesignTokens.caption.weight(.medium))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text(L10n.string(provider.title))
                        .font(DesignTokens.bodyText)
                        .foregroundStyle(Palette.ink)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(L10n.string("Provider"))
        .accessibilityValue(L10n.string(provider.title))
        .accessibilityIdentifier("connections.provider")
    }
}
