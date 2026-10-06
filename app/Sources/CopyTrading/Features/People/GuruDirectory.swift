import DesktopCore

/// The gurus a saved setup copies, with where they post and where their calls go.
struct GuruDirectory {
    struct Guru: Identifiable, Equatable {
        let id: String
        let name: String
        let channels: [String]
        let destinations: [TradingRouteConnection]
    }

    let gurus: [Guru]

    init(_ configuration: TradingConfiguration?) {
        guard let configuration else {
            gurus = []
            return
        }
        var byID: [String: Guru] = [:]
        for route in configuration.routes {
            let profile = configuration.profiles.first { $0.guruID == route.guruID }
            let name = profile?.displayName ?? route.guruID
            let existing = byID[route.guruID]
            byID[route.guruID] = Guru(
                id: route.guruID,
                name: name,
                channels: Array(Set((existing?.channels ?? []) + [route.channelID])).sorted(),
                destinations: (existing?.destinations ?? []) + route.connections
            )
        }
        gurus = byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The post as a person would read it in a list: no @everyone.
    func preview(of item: SourceActivity) -> String {
        item.readableText()
    }

    func name(for guruID: String?) -> String? {
        guard let guruID else { return nil }
        return gurus.first { $0.id == guruID }?.name
    }
}
