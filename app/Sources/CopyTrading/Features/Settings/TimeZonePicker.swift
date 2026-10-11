import SwiftUI

/// Every time zone, searchable by city ("Tokyo") or name ("Pacific Time").
struct TimeZonePicker: View {
    let choose: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private struct Zone: Identifiable {
        let id: String
        let city: String
        let name: String
    }

    private var zones: [Zone] {
        let all = TimeZone.knownTimeZoneIdentifiers.compactMap { identifier -> Zone? in
            guard let zone = TimeZone(identifier: identifier) else { return nil }
            let city = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
            return Zone(id: identifier, city: city, name: AppTime.name(zone))
        }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.city.localizedCaseInsensitiveContains(needle) || $0.name.localizedCaseInsensitiveContains(needle)
                || $0.id.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        SheetScaffold(
            kind: L10n.string("Settings"),
            title: L10n.string("Time Zone"),
            lede: L10n.string("Search every zone by city or name.")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TextField(
                    L10n.string("Search"), text: $query, prompt: Text(L10n.string("City or time zone")).foregroundStyle(Palette.tertiaryInk)
                )
                .labelsHidden()
                .underlineField()
                .padding(.bottom, 12)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(zones) { zone in
                        Button {
                            choose(zone.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.city)
                                    .font(DesignTokens.rowTitle)
                                    .foregroundStyle(Palette.ink)
                                Text(zone.name)
                                    .font(DesignTokens.caption)
                                    .foregroundStyle(Palette.tertiaryInk)
                            }
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(QuietPressButtonStyle())
                        .accessibilityIdentifier("timeZone.\(zone.id)")
                    }
                }
            }
        } actions: {
            Button(L10n.string("Cancel")) { dismiss() }
                .buttonStyle(SheetButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 600)
    }
}
