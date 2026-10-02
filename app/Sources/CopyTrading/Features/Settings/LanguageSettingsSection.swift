import SwiftUI

struct LanguageSettingsSection: View {
    @Environment(AppLanguagePreference.self) private var preference

    private var selection: Binding<AppLanguage> {
        Binding(
            get: { preference.language },
            set: { preference.select($0) }
        )
    }

    var body: some View {
        SettingsSection(title: L10n.string("Language")) {
            SettingsPickerRow(
                label: L10n.string("App language"),
                selection: selection,
                options: AppLanguage.allCases,
                identifier: "settings.language",
                title: { L10n.string($0.displayNameSourceText) }
            )
        }
    }
}
