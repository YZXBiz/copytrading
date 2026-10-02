import Foundation

/// One value on an equity curve: dollars for a combined curve, percent for an account's change.
public struct EquityCurvePoint: Equatable, Sendable {
    public let at: Date
    public let value: Double

    public init(at: Date, value: Double) {
        self.at = at
        self.value = value
    }
}

/// A stretch of the curve that stays on one side of its reference value.
public struct EquityCurveSegment: Equatable, Sendable {
    /// True at or above the reference: a gain, or no change.
    public let gain: Bool
    /// Points in time order; a segment that starts or ends at a crossing includes the exact
    /// interpolated point where the curve meets the reference, so adjacent segments join.
    public let points: [EquityCurvePoint]

    public init(gain: Bool, points: [EquityCurvePoint]) {
        self.gain = gain
        self.points = points
    }
}

/// What a stretch of the curve did: where it opened and ended, its extremes, and its worst fall.
public struct EquityCurveStats: Equatable, Sendable {
    public let open: EquityCurvePoint
    public let last: EquityCurvePoint
    public let high: EquityCurvePoint
    public let low: EquityCurvePoint
    /// The value changes are measured from: the previous close for a day, else the first point.
    public let reference: Double
    /// The largest fall from a running high to a later low, in dollars; zero when it never fell.
    public let maxDrawdown: Double
    /// The same fall as a fraction of the high it fell from.
    public let maxDrawdownFraction: Double

    public var change: Double { last.value - reference }
    public var changeFraction: Double? { reference == 0 ? nil : change / reference }
}

/// The change between two points a reader picked on the curve, earlier point first.
public struct EquityCurveMeasure: Equatable, Sendable {
    public let start: EquityCurvePoint
    public let end: EquityCurvePoint

    public var change: Double { end.value - start.value }
    public var changeFraction: Double? { start.value == 0 ? nil : change / start.value }
    public var duration: TimeInterval { end.at.timeIntervalSince(start.at) }
}

/// The combined equity of several accounts over one window, with the math a chart reads from it.
public struct EquityCurve: Equatable, Sendable {
    public let points: [EquityCurvePoint]
    /// The broker's previous close for a day window; nil for longer ranges or when an account lacks it.
    public let baseline: Double?

    public init(points: [EquityCurvePoint], baseline: Double?) {
        self.points = points
        self.baseline = baseline
    }

    /// Accounts report on the same broker clock, so values are summed only at times where every
    /// account has a point; a time missing from one account would otherwise read as a drop.
    public init(combining histories: [EquityHistory]) {
        guard !histories.isEmpty else {
            self.init(points: [], baseline: nil)
            return
        }
        var sums: [Date: (total: Double, count: Int)] = [:]
        for history in histories {
            for point in history.points {
                guard let at = EquityCurve.date(point.at), let value = EquityCurve.amount(point.equity) else { continue }
                let current = sums[at] ?? (0, 0)
                sums[at] = (current.total + value, current.count + 1)
            }
        }
        let points = EquityCurve.fundedFromFirstBalance(
            sums
                .filter { $0.value.count == histories.count }
                .map { EquityCurvePoint(at: $0.key, value: $0.value.total) }
                .sorted { $0.at < $1.at }
        )
        let isDay = histories.allSatisfy { $0.window.range == .day }
        let bases = histories.compactMap { EquityCurve.amount($0.baseValue) }
        let baseline = isDay && bases.count == histories.count ? bases.reduce(0, +) : nil
        self.init(points: points, baseline: baseline)
    }

    /// One account's change from its own reference as a fraction, so accounts of any size compare.
    public init(changeOf history: EquityHistory) {
        let points = EquityCurve.fundedFromFirstBalance(
            history.points.compactMap { point -> EquityCurvePoint? in
                guard let at = EquityCurve.date(point.at), let value = EquityCurve.amount(point.equity) else { return nil }
                return EquityCurvePoint(at: at, value: value)
            }
            .sorted { $0.at < $1.at }
        )
        let base = history.window.range == .day ? EquityCurve.amount(history.baseValue) : nil
        guard let reference = base ?? points.first?.value, reference != 0 else {
            self.init(points: [], baseline: nil)
            return
        }
        self.init(
            points: points.map { EquityCurvePoint(at: $0.at, value: ($0.value - reference) / reference) },
            baseline: 0
        )
    }

    /// The value changes are measured from: the baseline when known, else the first point.
    public var reference: Double? { baseline ?? points.first?.value }

    public var stats: EquityCurveStats? {
        guard let open = points.first, let last = points.last, let reference else { return nil }
        var high = open
        var low = open
        var peak = open.value
        var drawdown = 0.0
        var drawdownFraction = 0.0
        for point in points {
            if point.value > high.value { high = point }
            if point.value < low.value { low = point }
            peak = max(peak, point.value)
            let fall = peak - point.value
            if fall > drawdown {
                drawdown = fall
                drawdownFraction = peak == 0 ? 0 : fall / peak
            }
        }
        return EquityCurveStats(
            open: open, last: last, high: high, low: low, reference: reference,
            maxDrawdown: drawdown, maxDrawdownFraction: drawdownFraction
        )
    }

    /// The curve split where it crosses `reference`, each piece gaining or losing.
    public func segments(around reference: Double) -> [EquityCurveSegment] {
        guard var current = points.first else { return [] }
        var gain = current.value >= reference
        var run = [current]
        var segments: [EquityCurveSegment] = []
        for next in points.dropFirst() {
            let nextGain = next.value >= reference
            if nextGain != gain {
                let crossing = EquityCurve.crossing(from: current, to: next, at: reference)
                run.append(crossing)
                segments.append(EquityCurveSegment(gain: gain, points: run))
                run = [crossing]
                gain = nextGain
            }
            run.append(next)
            current = next
        }
        segments.append(EquityCurveSegment(gain: gain, points: run))
        return segments
    }

    /// The recorded point closest in time to `date`.
    public func nearest(to date: Date) -> EquityCurvePoint? {
        points.min { abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date)) }
    }

    /// The change between the recorded points nearest to two chosen times, in either order.
    public func measure(from first: Date, to second: Date) -> EquityCurveMeasure? {
        guard let a = nearest(to: min(first, second)), let b = nearest(to: max(first, second)), a.at < b.at else {
            return nil
        }
        return EquityCurveMeasure(start: a, end: b)
    }

    private static func crossing(from a: EquityCurvePoint, to b: EquityCurvePoint, at level: Double) -> EquityCurvePoint {
        let span = b.value - a.value
        let fraction = span == 0 ? 0 : (level - a.value) / span
        let seconds = b.at.timeIntervalSince(a.at) * fraction
        return EquityCurvePoint(at: a.at.addingTimeInterval(seconds), value: level)
    }

    /// Brokers report zero equity for the days before an account was funded. Those days are not a
    /// balance of nothing that later grew; the account did not exist yet, so the curve starts at the
    /// first positive balance. A balance that falls to zero after that is a real loss and stays.
    static func fundedFromFirstBalance(_ points: [EquityCurvePoint]) -> [EquityCurvePoint] {
        guard let first = points.firstIndex(where: { $0.value > 0 }) else { return [] }
        return Array(points[first...])
    }

    static func date(_ iso: String) -> Date? {
        if let date = try? Date(iso, strategy: .iso8601) { return date }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso)
    }

    static func amount(_ text: String?) -> Double? {
        guard let text, let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }
}

/// The US equity market's trading sessions, in exchange (New York) time.
public enum MarketSession: String, CaseIterable, Sendable {
    case preMarket
    case regular
    case afterHours

    /// Exchange time, so the day reads the same wherever the trader's Mac is.
    public static let timeZone = TimeZone(identifier: "America/New_York")!

    /// Minutes after midnight in exchange time; standard hours, not half-day closes.
    var minutes: Range<Int> {
        switch self {
        case .preMarket: 4 * 60..<9 * 60 + 30
        case .regular: 9 * 60 + 30..<16 * 60
        case .afterHours: 16 * 60..<20 * 60
        }
    }

    /// The session `date` falls in, or nil when the market is closed.
    public static func of(_ date: Date) -> MarketSession? {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return allCases.first { $0.minutes.contains(minute) }
    }

    /// The whole extended trading day (4:00 to 20:00 exchange time) that contains `date`.
    public static func tradingDay(containing date: Date) -> ClosedRange<Date> {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: 4 * 60, to: day)!...calendar.date(byAdding: .minute, value: 20 * 60, to: day)!
    }

    /// When this session runs on the exchange day that contains `date`.
    public func interval(on date: Date) -> ClosedRange<Date> {
        let day = Self.calendar.startOfDay(for: date)
        return Self.calendar.date(byAdding: .minute, value: minutes.lowerBound, to: day)!...Self.calendar.date(
            byAdding: .minute, value: minutes.upperBound, to: day)!
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
