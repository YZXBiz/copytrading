import Foundation

enum ConnectionsEditingTarget: Identifiable, Hashable {
    case account(UUID)
    case route(UUID)

    var id: Self { self }
}
