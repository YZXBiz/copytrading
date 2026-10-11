import DesktopCore

/// Why the owner opened the sheet: to approve a call an account held for approval, to copy calls
/// the post waits on, or to say what a post the reader couldn't read should do.
enum ManualReviewMode: Equatable {
    case approve
    case copy
    case enter

    init(copying: WaitingCall?) {
        guard let copying, !copying.calls.isEmpty else {
            self = .enter
            return
        }
        self = copying.awaitsApproval ? .approve : .copy
    }

    /// The tracked label over the post.
    var label: String {
        switch self {
        case .approve: "Approve a call"
        case .copy: "Copy a call"
        case .enter: "Enter the trade"
        }
    }

    /// What the correction records as its reason, in the owner's words.
    var reason: String {
        switch self {
        case .approve, .copy: "Copied a call that was waiting for me"
        case .enter: "Entered the trade the post asked for"
        }
    }
}
