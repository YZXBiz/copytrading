import DesktopCore

enum ActivitySheet: Identifiable {
    case manualReview(SourceActivity)
    case historicalEvaluation(SourceActivity)

    var id: String {
        switch self {
        case .manualReview(let source): "review:\(source.id)"
        case .historicalEvaluation(let source): "evaluation:\(source.id)"
        }
    }
}
