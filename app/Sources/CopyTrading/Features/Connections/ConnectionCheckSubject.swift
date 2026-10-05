/// One connection Connections checks on its own: a service, or a broker account by its name.
enum ConnectionCheckSubject: Hashable {
    case discord
    case interpreter
    case alerts
    case account(String)

    init(_ kind: ConnectionKind) {
        switch kind {
        case .discord: self = .discord
        case .interpreter: self = .interpreter
        case .alerts: self = .alerts
        }
    }
}
