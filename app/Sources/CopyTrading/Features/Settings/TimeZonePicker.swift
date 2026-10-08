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
        NavigationStack {
            List(zones) { zone in
                Button {
                    choose(zone.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zone.city).foregroundStyle(Palette.ink)
                        Text(zone.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeZone.\(zone.id)")
            }
            .searchable(text: $query, prompt: Text(L10n.string("City or time zone")))
            .navigationTitle(L10n.string("Time Zone"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
    }
}
