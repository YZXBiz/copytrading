/// One stop on a route, such as a post's way to an order or a setup's steps, and how it is doing.
struct RouteStop: Identifiable {
    let title: String
    let state: String
    let tone: StatusTone
    var id: String { title }
    /// A stop that wants the owner's eye says its state in ink.
    var needsLook: Bool { tone == .caution || tone == .critical }
}
