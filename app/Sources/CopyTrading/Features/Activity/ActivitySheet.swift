import DesktopCore

enum ActivitySheet: Identifiable {
    /// Review a post, or copy the calls it waits on when `copying` is given.
    case manualReview(SourceActivity, copying: WaitingCall?)
    case historicalEvaluation(SourceActivity)

    var id: String {
        switch self {
        case .manualReview(let source, _): "review:\(source.id)"
        case .historicalEvaluation(let source): "evaluation:\(source.id)"
        }
    }
}
