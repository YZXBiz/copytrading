import SwiftUI

/// Which time zone the app shows times in: the Mac's own (the default, which follows the Mac),
/// New York's market time, or any zone picked from the list.
struct TimeZoneSettingsSection: View {
    @State private var preference = AppTimeZonePreference.shared
    @State private var isPicking = false

    private enum Choice: Hashable {
        case automatic
        case newYork
        case other(String)
    }

    private var options: [Choice] {
        var options: [Choice] = [.automatic, .newYork]
        if let chosen = preference.chosen, chosen != AppTimeZonePreference.newYork { options.append(.other(chosen)) }
        return options
    }

    private var selection: Binding<Choice> {
        Binding(
            get: {
                switch preference.chosen {
                case nil: .automatic
                case AppTimeZonePreference.newYork: .newYork
                case let other?: .other(other)
                }
            },
            set: { choice in
                switch choice {
                case .automatic: preference.select(nil)
                case .newYork: preference.select(AppTimeZonePreference.newYork)
                case .other(let identifier): preference.select(identifier)
                }
            })
    }

    var body: some View {
        SettingsSection(title: L10n.string("Time Zone")) {
            SettingsPickerRow(
                label: L10n.string("Show times in"),
                selection: selection,
                options: options,
                detail: L10n.string("Post times, deadlines, and market hours use this zone."),
                identifier: "settings.timeZone",
                title: title
            )
            SettingsActionRow(
                title: "Choose Another Time Zone…",
                detail: "Search every zone by city or name."
            ) { isPicking = true }
        }
        .sheet(isPresented: $isPicking) {
            TimeZonePicker { identifier in
                preference.select(identifier)
                isPicking = false
            }
        }
    }

    private func title(_ choice: Choice) -> String {
        switch choice {
        case .automatic:
            L10n.string("Automatic (%@)", AppTime.name(.autoupdatingCurrent))
        case .newYork:
            L10n.string("New York (market time)")
        case .other(let identifier):
            TimeZone(identifier: identifier).map { AppTime.name($0) } ?? identifier
        }
    }
}
