/// Where a Connections panel grew from, and shrinks back into when it closes.
enum ConnectionPanelOrigin: Hashable {
    /// The ⊕ beside the page title.
    case newConnection
    /// A section's offer card or its tile.
    case section(ConnectionKind)
}
