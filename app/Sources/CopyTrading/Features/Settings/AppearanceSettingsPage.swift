import SwiftUI

/// Light, dark, or the Mac's own appearance, chosen from pictures, and where to make
/// motion and transparency calmer.
struct AppearanceSettingsPage: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 0) {
                ForEach(AppAppearance.allCases) { option in
                    choice(option)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 12)
            .background(Palette.well, in: .rect(cornerRadius: 14, style: .continuous))

            SettingsSection(
                title: "Motion and Transparency",
                subtitle: "CopyTrading follows Reduce Motion, Reduce Transparency, and Increase Contrast from your Mac."
            ) {
                SettingsActionRow(
                    title: "Open Accessibility Settings",
                    detail: "Clouds hold still, glass turns solid, and edges get stronger."
                ) {
                    openURL(URL(literal: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display"))
                }
            }
        }
        .onChange(of: appearance) { _, chosen in
            chosen.apply()
        }
    }

    private func choice(_ option: AppAppearance) -> some View {
        let isSelected = appearance == option
        return Button {
            appearance = option
        } label: {
            VStack(spacing: 10) {
                AppearanceThumbnail(appearance: option)
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 2.5)
                    }
                Text(L10n.string(option.title))
                    .font(.system(.body, weight: .semibold).scaled(by: 14.0 / 13))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.ink)
            }
            .contentShape(.rect)
        }
        .buttonStyle(QuietPressButtonStyle())
        .accessibilityLabel(L10n.string(option.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(option.rawValue)")
    }
}
