import Foundation

/// Round, evenly spaced value ticks and the precision their labels need.
struct EquityValueAxis {
    let ticks: [Double]
    let step: Double

    /// About `count` ticks on 1, 2, or 5 × a power of ten, inside `lower...upper`.
    init(lower: Double, upper: Double, count: Int = 4) {
        let span = upper - lower
        guard span > 0, count > 0 else {
            ticks = [lower]
            step = 0
            return
        }
        let raw = span / Double(count)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let unit: Double = normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10
        let step = unit * magnitude
        // Whole multiples of the step, so no tick drifts off its round number, and zero is +0: a
        // range just below zero rounds up to -0, which reads "-$0".
        var index = (lower / step).rounded(.up)
        var ticks: [Double] = []
        while index * step <= upper + step * 1e-9 {
            let value = index * step
            ticks.append(value.isZero ? 0 : value)
            index += 1
        }
        self.ticks = ticks
        self.step = step
    }

    /// Dollars at whole-dollar precision unless the ticks are closer than a dollar apart.
    func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(step < 1 ? 2 : 0)))
    }

    /// A fraction as a percent with only as many decimals as the spacing needs.
    func percent(_ value: Double) -> String {
        let digits = step >= 0.01 ? 0 : step >= 0.001 ? 1 : 2
        return value.formatted(.percent.precision(.fractionLength(digits)).sign(strategy: .always(includingZero: false)))
    }
}
