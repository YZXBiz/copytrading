import Foundation

/// One run of the post along the journey's path, from one stop to another, measured in stops
/// (1.5 is halfway between the second and third). It ends, so nothing redraws once it arrives.
struct GuideJourneyTrip: Hashable {
    let from: Double
    let to: Double
    let start: Date
    let seconds: Double

    init(from: Int, to: Int, start: Date = .now) {
        self.from = Double(from)
        self.to = Double(to)
        self.start = start
        self.seconds = min(3.2, max(0.6, abs(Double(to - from)) * 0.55))
    }

    /// How far along the trip is at `date`, eased, from 0 to 1.
    func progress(at date: Date) -> Double {
        let t = min(1, max(0, date.timeIntervalSince(start) / seconds))
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    /// Where the post is, in stops, at `date`.
    func position(at date: Date) -> Double {
        from + (to - from) * progress(at: date)
    }
}
