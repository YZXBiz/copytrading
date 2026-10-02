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
        var value = (lower / step).rounded(.up) * step
        var ticks: [Double] = []
        while value <= upper + step * 1e-9 {
            ticks.append(value)
            value += step
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

    /// Ticks far enough from `value` that its tag does not cover their labels.
    func ticks(clearOf value: Double?, within fraction: Double = 0.45) -> [Double] {
        guard let value, step > 0 else { return ticks }
        return ticks.filter { abs($0 - value) > step * fraction }
    }
}
