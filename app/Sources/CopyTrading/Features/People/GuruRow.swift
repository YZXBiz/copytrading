import SwiftUI

struct GuruRow: View {
    let guru: GuruDirectory.Guru
    let stats: GuruStats

    var body: some View {
        HStack(spacing: 12) {
            GuruMonogram(name: guru.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(guru.name)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @MainActor private var subtitle: String {
        guard let last = stats.lastPost else { return L10n.string("No posts loaded yet") }
        return L10n.string(
            "Last post %@",
            last.formatted(.relative(presentation: .named).locale(AppLanguagePreference.shared.language.locale))
        )
    }
}
