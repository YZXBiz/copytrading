/// What the Connections panel shows: the "Create New" picker, or one service's
/// settings.
enum ConnectionPanelPage: Hashable {
    /// Every service CopyTrading can connect to.
    case catalog
    /// Every interpreter, grouped: the popular ones, more hosted services, and your own model.
    case interpreters
    case editor(ConnectionKind)
}
