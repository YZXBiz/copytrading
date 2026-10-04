import DesktopCore

/// Where a Connections panel grew from, and shrinks back into when it closes.
enum ConnectionPanelOrigin: Hashable {
    /// A section's row for a service.
    case section(ConnectionKind)
    /// An interpreter service's own row, before any interpreter is set up.
    case provider(TradingProviderName)
    /// An alert service's own row.
    case alert(TradingAlertService)
}
