import Observation

/// What the reader is inspecting on the chart, held apart from the curve so a hover redraws only
/// the marks and the readout that read it, never the line under them.
@MainActor
@Observable
final class EquityPointer {
    var selection = EquitySelection.none
}
